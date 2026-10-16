//
//  TelemetryManager.swift
//  InstitutionalApp
//
//  Telemetría periódica y envío de estado a /api/telemetry.php (batería, wifi, gps, etc.).
//  Compatible iOS 17+, Swift 5.9
//

import Foundation
import UIKit
import Combine
import BackgroundTasks
import CoreLocation

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
    private var timerCancellable: AnyCancellable?
    
    private var refreshTaskIdentifier = "com.institutional.supervision.telemetry-refresh"
    private var processingTaskIdentifier = "com.institutional.supervision.telemetry-processing"
    
    private var isStarted = false
    
    func start() {
        guard !isStarted else { return }
        isStarted = true
        
        Task { @MainActor in self.isUpdating = true }
        
        // Habilitar monitoreo de batería
        DispatchQueue.main.async {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        
        // 1. Envío inicial inmediato
        sendTelemetryNow()
        
        // 2. Timer continuo en foreground (cada 20 segundos)
        timerCancellable = Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendTelemetryNow()
            }
        
        // 3. Reaccionar a cambios de batería
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.sendTelemetryNow() }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .sink { [weak self] _ in self?.sendTelemetryNow() }
            .store(in: &cancellables)
            
        // 4. Reaccionar a cambios de red
        NotificationCenter.default.publisher(for: .networkStatusChanged)
            .debounce(for: .seconds(3), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.sendTelemetryNow() }
            .store(in: &cancellables)
            
        // 5. Reaccionar a Push silencioso
        NotificationCenter.default.publisher(for: .institucionalSilentPush)
            .sink { [weak self] _ in self?.sendTelemetryNow() }
            .store(in: &cancellables)
            
        // Tareas en segundo plano
        scheduleRefreshTask()
        scheduleProcessingTask()
        
        logEvent(type: "device_boot", meta: ["source": "app_start"])
    }
    
    // MARK: - Envío de Telemetría Real a /api/telemetry.php
    
    func sendTelemetryNow() {
        Task {
            let payload = await buildTelemetryPayload()
            
            await MainActor.run { self.isSending = true }
            defer { Task { @MainActor in self.isSending = false } }
            
            do {
                let response = try await apiClient.sendTelemetry(payload)
                await MainActor.run {
                    self.lastSent = Date()
                }
                
                // Si el servidor devolvió comandos pendientes, procesarlos
                if let cmds = response["commands"] as? [[String: Any]], !cmds.isEmpty {
                    await processCommands(cmds)
                }
            } catch {
                print("Error enviando telemetría al servidor: \(error)")
            }
        }
    }
    
    private func buildTelemetryPayload() async -> [String: Any] {
        var payload: [String: Any] = [:]
        
        // Batería en MainActor
        let (bat, isCharging, model, systemVersion) = await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let rawBat = UIDevice.current.batteryLevel
            let b = rawBat >= 0 ? Int(rawBat * 100) : 100
            let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
            return (b, charging, UIDevice.currentModelCommercial, UIDevice.current.systemVersion)
        }
        
        payload["battery"] = bat
        payload["charging"] = isCharging ? 1 : 0
        payload["model"] = model
        payload["system_version"] = systemVersion
        
        // Red y Conexión
        let netType = networkMonitor.connectionType.rawValue
        payload["conn"] = netType
        payload["net_type"] = netType
        payload["data_enabled"] = (netType == "cellular") ? 1 : 0
        if netType == "wifi" {
            payload["wifi_ssid"] = "Wi-Fi"
        }
        
        // Ubicación GPS
        if let loc = LocationManager.shared.lastLocation {
            payload["lat"] = loc.coordinate.latitude
            payload["lng"] = loc.coordinate.longitude
            payload["accuracy"] = loc.horizontalAccuracy
            payload["speed"] = loc.speed >= 0 ? loc.speed * 3.6 : 0 // km/h
            payload["loc_enabled"] = 1
        } else {
            let hasLocAuth = LocationManager.shared.authorizationStatus == .authorizedAlways || LocationManager.shared.authorizationStatus == .authorizedWhenInUse
            payload["loc_enabled"] = hasLocAuth ? 1 : 0
            if hasLocAuth {
                LocationManager.shared.refreshLocation()
            }
        }
        
        // Estado y Metadatos
        payload["foreground_app"] = "Empresas"
        payload["platform"] = "ios"
        payload["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        payload["ts"] = Int64(Date().timeIntervalSince1970 * 1000)
        
        return payload
    }
    
    private func processCommands(_ cmds: [[String: Any]]) async {
        for cmd in cmds {
            guard let type = cmd["type"] as? String else { continue }
            print("Comando remoto recibido: \(type)")
            if type == "locate" {
                LocationManager.shared.startUpdating()
            }
        }
    }
    
    // MARK: - Compatibilidad con EventLogger y BackgroundTasks
    
    func collectAndSendTelemetry(includeHeavy: Bool = false) async {
        sendTelemetryNow()
    }
    
    func flushEvents() {
        sendTelemetryNow()
    }
    
    func logEvent(type: String, meta: [String: Any] = [:]) {
        eventLogger.log(type: type, meta: meta)
    }
    
    private func scheduleRefreshTask() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    
    private func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: processingTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }
    
    func scheduleBackgroundRefresh() {
        scheduleRefreshTask()
    }
    
    func performDailyProcessing() async {
        sendTelemetryNow()
    }
    
    func scheduleDailyProcessing() {
        scheduleProcessingTask()
    }
    
    func saveState() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "telemetry_last_state")
    }
}