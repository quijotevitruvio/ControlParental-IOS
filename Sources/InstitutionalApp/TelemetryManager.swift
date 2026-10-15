//
//  TelemetryManager.swift
//  InstitutionalApp
//
//  Telemetría periódica y envío de eventos institucionales.
//  Compatible iOS 17+, Swift 5.9
//

import Foundation
import UIKit
import Combine
import BackgroundTasks

final class TelemetryManager: ObservableObject {
    static let shared = TelemetryManager()
    
    @Published var lastSent: Date?
    @Published var isUpdating: Bool = false
    @Published var isSending: Bool = false
    
    private let apiClient = APIClient.shared
    private let eventLogger = EventLogger.shared
    private let locationManager = LocationManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    
    private var refreshTaskIdentifier = "com.institutional.supervision.telemetry-refresh"
    private var processingTaskIdentifier = "com.institutional.supervision.telemetry-processing"
    
    private var isStarted = false
    
    func start() {
        guard !isStarted else { return }
        isStarted = true
        
        Task { @MainActor in self.isUpdating = true }
        scheduleRefreshTask()
        scheduleProcessingTask()
        
        NotificationCenter.default.publisher(for: .institucionalSilentPush)
            .sink { [weak self] _ in self?.flushEvents() }
            .store(in: &cancellables)
        
        logEvent(type: "device_boot", meta: ["source": "app_start"])
        flushEvents()
    }
    
    private func scheduleRefreshTask() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        try? BGTaskScheduler.shared.submit(request)
    }
    
    private func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: processingTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hora
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }
    
    func collectAndSendTelemetry(includeHeavy: Bool = false) async {
        let payload = await buildPayload(includeHeavy: includeHeavy)
        eventLogger.log(type: "telemetry", meta: payload)
        
        if NetworkMonitor.shared.isConnected {
            flushEvents()
        }
    }
    
    private func buildPayload(includeHeavy: Bool) async -> [String: Any] {
        var payload: [String: Any] = [:]
        
        // Batería en MainActor
        let (battery, isCharging, model, systemVersion) = await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let bat = Int(UIDevice.current.batteryLevel * 100)
            let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
            return (bat, charging, UIDevice.current.model, UIDevice.current.systemVersion)
        }
        payload["battery"] = battery
        payload["charging"] = isCharging
        payload["model"] = model
        payload["system_version"] = systemVersion
        
        // Red
        let netInfo = await NetworkMonitor.shared.currentNetworkInfo()
        payload.merge(netInfo) { _, new in new }
        
        // Ubicación
        if let loc = LocationManager.shared.lastLocation {
            payload["lat"] = loc.coordinate.latitude
            payload["lng"] = loc.coordinate.longitude
            payload["accuracy"] = loc.horizontalAccuracy
            payload["speed"] = loc.speed >= 0 ? loc.speed * 3.6 : 0 // km/h
        }
        
        // DeviceActivity (Screen Time)
        if #available(iOS 16.0, *) {
            if let activity = DeviceActivityManager.shared.dailySummaryForTelemetry() {
                payload["device_activity"] = activity
            }
        }
        
        payload["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
        
        return payload
    }
    
    func flushEvents() {
        Task {
            let events = await EventLogger.shared.pendingEvents()
            guard !events.isEmpty else { return }
            
            await MainActor.run { self.isSending = true }
            defer { Task { @MainActor in self.isSending = false } }
            
            do {
                let dicts = events.map { $0.asDictionary }
                let success = try await APIClient.shared.sendInstitutionEvents(dicts)
                if success {
                    await EventLogger.shared.markAsSent(events)
                    await MainActor.run {
                        self.lastSent = Date()
                    }
                }
            } catch {
                // Se queda en cola para próximo intento
            }
            
            scheduleRefreshTask()
            scheduleProcessingTask()
        }
    }
    
    func logEvent(type: String, meta: [String: Any] = [:]) {
        eventLogger.log(type: type, meta: meta)
    }
    
    func detectEvasionEvents() {
        if NetworkMonitor.shared.isVPNActive {
            logEventOnce(type: "vpn_detected", key: "vpn", meta: ["app": "vpn", "net_type": "vpn"])
        }
        
        logEventOnce(type: "device_boot", key: "boot", windowMs: 60 * 60 * 1000)
    }
    
    private func logEventOnce(type: String, key: String, windowMs: Int64 = 900_000, meta: [String: Any] = [:]) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let keyName = "inst_last_\(key)"
        let last = UserDefaults.standard.value(forKey: keyName) as? Int64 ?? 0
        if now - last >= windowMs {
            UserDefaults.standard.set(now, forKey: keyName)
            logEvent(type: type, meta: meta)
        }
    }
    
    func scheduleBackgroundRefresh() {
        scheduleRefreshTask()
    }
    
    func performDailyProcessing() async {
        await collectAndSendTelemetry(includeHeavy: true)
        flushEvents()
    }
    
    func scheduleDailyProcessing() {
        scheduleProcessingTask()
    }
    
    func saveState() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "telemetry_last_state")
    }
}