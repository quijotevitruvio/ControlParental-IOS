//
//  TelemetryManager.swift
//  InstitutionalApp
//
//  Telemetría periódica y envío de eventos institucionales.
//  Compatible iOS 17+, Swift 5.9
//

import Foundation
import Combine
import BackgroundTasks

final class TelemetryManager {
    static let shared = TelemetryManager()
    
    private let apiClient = APIClient.shared
    private let eventLogger = EventLogger.shared
    private let locationManager = LocationManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    
    private var refreshTaskIdentifier = "com.institucional.telemetry.refresh"
    private var processingTaskIdentifier = "com.institucional.telemetry.processing"
    
    private init() {}
    
    func start() {
        registerBackgroundTasks()
        scheduleRefreshTask()
        scheduleProcessingTask()
        
        // Escuchar push silencioso para flush inmediato
        NotificationCenter.default.publisher(for: .institucionalSilentPush)
            .sink { [weak self] _ in self?.flushEvents() }
            .store(in: &cancellables)
        
        // Evento de arranque
        logEvent(type: "device_boot", meta: ["source": "app_start"])
        flushEvents()
    }
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { task in
            self.handleRefreshTask(task as! BGAppRefreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingTaskIdentifier, using: nil) { task in
            self.handleProcessingTask(task as! BGProcessingTask)
        }
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
    
    private func handleRefreshTask(_ task: BGAppRefreshTask) {
        scheduleRefreshTask() // Re-agendar
        
        task.expirationHandler = { self.flushEvents() }
        
        Task {
            await self.collectAndSendTelemetry()
            task.setTaskCompleted(success: true)
        }
    }
    
    private func handleProcessingTask(_ task: BGProcessingTask) {
        scheduleProcessingTask()
        
        task.expirationHandler = { self.flushEvents() }
        
        Task {
            await self.collectAndSendTelemetry(includeHeavy: true)
            self.flushEvents()
            task.setTaskCompleted(success: true)
        }
    }
    
    func collectAndSendTelemetry(includeHeavy: Bool = false) async {
        let payload = await buildPayload(includeHeavy: includeHeavy)
        
        // Guarda en cola offline
        await eventLogger.log(type: "telemetry", meta: payload)
        
        // Si hay red, intenta enviar
        if NetworkMonitor.shared.isConnected {
            await flushEvents()
        }
    }
    
    private func buildPayload(includeHeavy: Bool) async -> [String: Any] {
        var payload: [String: Any] = [:]
        
        // Batería
        await UIDevice.current.isBatteryMonitoringEnabled = true
        payload["battery"] = Int(UIDevice.current.batteryLevel * 100)
        payload["charging"] = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        
        // Red
        if let netInfo = await NetworkMonitor.shared.currentNetworkInfo() {
            payload.merge(netInfo) { _, new in new }
        }
        
        // Ubicación (si permiso concedido)
        if let loc = LocationManager.shared.lastLocation {
            payload["lat"] = loc.coordinate.latitude
            payload["lng"] = loc.coordinate.longitude
            payload["accuracy"] = loc.horizontalAccuracy
            payload["speed"] = loc.speed >= 0 ? loc.speed * 3.6 : 0 // km/h
        }
        
        // DeviceActivity (Screen Time) - agregados
        if #available(iOS 16.0, *) {
            if let activity = await DeviceActivityManager.shared.fetchDailySummary() {
                payload["device_activity"] = activity
            }
        }
        
        // Info extra
        payload["model"] = UIDevice.current.model
        payload["system_version"] = UIDevice.current.systemVersion
        payload["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
        
        if includeHeavy {
            // Apps instaladas (solo nombres/IDs públicos)
            // Requiere entitlement com.apple.developer.managed-apps
        }
        
        return payload
    }
    
    func flushEvents() {
        Task {
            let events = await EventLogger.shared.pendingEvents()
            guard !events.isEmpty else { return }
            
            do {
                let success = try await APIClient.shared.sendInstitutionEvents(events)
                if success {
                    await EventLogger.shared.markAsSent(events)
                }
            } catch {
                // Se queda en cola para próximo intento
            }
            
            // Re-agenda tareas
            scheduleRefreshTask()
            scheduleProcessingTask()
        }
    }
    
    // MARK: - Eventos de riesgo/anti-evasión
    
    func logEvent(type: String, meta: [String: Any] = [:]) {
        let event: [String: Any] = [
            "type": type,
            "occurred_at": ISO8601DateFormatter().string(from: Date()),
            "meta": meta
        ]
        Task { await eventLogger.log(type: type, meta: ["event": type]) }
    }
    
    func detectEvasionEvents() {
        // VPN detection
        if NetworkMonitor.shared.isVPNActive {
            logEventOnce(type: "vpn_detected", key: "vpn", meta: ["app": "vpn", "net_type": "vpn"])
        }
        
        // Airplane mode
        let airplaneOn = UserDefaults.standard.bool(forKey: "airplane_mode_on") // placeholder
        // En iOS real se detecta via CTTelephonyNetworkInfo o NotificationCenter
        
        // Device boot
        logEventOnce(type: "device_boot", key: "boot", windowMs: 60 * 60 * 1000)
    }
    
    private func logEventOnce(type: String, key: String, windowMs: Int64 = 900_000, meta: [String: Any] = [:]) {
        let now = Date().timeIntervalSince1970 * 1000
        let keyName = "inst_last_\(key)"
        let last = UserDefaults.standard.value(forKey: keyName) as? Int64 ?? 0
        if now - last >= windowMs {
            UserDefaults.standard.set(Int64(now), forKey: keyName)
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
    
    func saveState() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "telemetry_last_state")
    }
}

// MARK: - Extensiones para notificaciones

extension Notification.Name {
    static let institucionalSilentPush = Notification.Name("institucionalSilentPush")
}