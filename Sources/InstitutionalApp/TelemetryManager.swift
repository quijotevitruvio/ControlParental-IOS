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
    
    func startPeriodicSync() {
        start()
    }
    
    // MARK: - Envío de Telemetría Real a /api/telemetry.php
    
    func sendTelemetryNow() {
        let bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "InstitutionalTelemetrySync") {
            // Background task expiration callback
        }
        
        Task {
            defer {
                if bgTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskId)
                }
            }
            
            let payload = await buildTelemetryPayload()
            
            await MainActor.run { self.isSending = true }
            defer { Task { @MainActor in self.isSending = false } }
            
            do {
                let response = try await apiClient.sendTelemetry(payload)
                await MainActor.run {
                    self.lastSent = Date()
                }
                
                // 1. Sincronizar políticas remotas (números bloqueados y geocercas)
                if let policy = response["policy"] as? [String: Any] {
                    await processPolicy(policy)
                }
                
                // 2. Si el servidor devolvió comandos pendientes, procesarlos
                if let cmds = response["commands"] as? [[String: Any]], !cmds.isEmpty {
                    await processCommands(cmds)
                }
                
                // 3. Vaciar cola de eventos offline pendientes tras conexión exitosa
                await self.flushEvents()
            } catch {
                print("Error enviando telemetría al servidor: \(error)")
            }
        }
    }
    
    private func processPolicy(_ policy: [String: Any]) async {
        // Sincronizar números bloqueados
        if let blocked = policy["blocked_numbers"] as? [String] {
            CallBlockerManager.shared.syncFromPolicy(blocked)
        } else if let blockedDict = policy["blocked_numbers"] as? [String: String] {
            CallBlockerManager.shared.syncFromPolicy(dict: blockedDict)
        }
        
        // Sincronizar geocercas
        if let rawZones = policy["geofences"] as? [[String: Any]] {
            let zones = rawZones.compactMap { GeofenceZone(dict: $0) }
            LocationManager.shared.syncGeofences(zones)
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
        
        // APNs / FCM token
        if let apns = ConfigManager.shared.apnsToken, !apns.isEmpty {
            payload["fcm_token"] = apns
            payload["apns_token"] = apns
        }
        
        // Estado de manipulación / Tamper status
        payload["tamper_status"] = [
            "passcode_set": ParentalAuthManager.shared.isPinSet,
            "supervised": ConfigManager.shared.isManaged,
            "jailbroken": false
        ]
        
        // Resumen de permisos para chips de estado en el panel web
        let hasLocAuth = LocationManager.shared.authorizationStatus == .authorizedAlways || LocationManager.shared.authorizationStatus == .authorizedWhenInUse
        let hasNotifications = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus == .authorized)
            }
        }
        payload["permissions"] = [
            "location_authorized": hasLocAuth,
            "notifications_enabled": hasNotifications,
            "accessibility": true,
            "location": hasLocAuth
        ]
        
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
    
    func flushEvents() async {
        guard networkMonitor.isConnected else { return }
        let pending = eventLogger.pendingEvents(limit: 100)
        guard !pending.isEmpty else { return }
        
        var locationEvents: [QueuedEvent] = []
        var institutionalEvents: [QueuedEvent] = []
        
        for ev in pending {
            if ev.type == "location" || ev.type == "location_update" {
                locationEvents.append(ev)
            } else {
                institutionalEvents.append(ev)
            }
        }
        
        // 1. Procesar eventos de ubicación offline formateados como room_logs
        if !locationEvents.isEmpty {
            var roomLogs: [[String: Any]] = []
            for ev in locationEvents {
                let meta = ev.metaDict
                let lat = (meta["lat"] as? Double) ?? (meta["latitude"] as? Double) ?? 0.0
                let lng = (meta["lng"] as? Double) ?? (meta["longitude"] as? Double) ?? 0.0
                let acc = (meta["accuracy"] as? Double) ?? (meta["horizontal_accuracy"] as? Double) ?? 0.0
                let alt = (meta["altitude"] as? Double) ?? 0.0
                let speed = (meta["speed"] as? Double) ?? (meta["speed_kmh"] as? Double) ?? 0.0
                let ts = Int64(ev.timestamp.timeIntervalSince1970 * 1000)
                
                let contentJson = "{\"lat\":\(lat),\"lng\":\(lng),\"acc\":\(acc),\"speed\":\(speed)}"
                roomLogs.append([
                    "type": "location",
                    "lat": lat,
                    "lng": lng,
                    "accuracy": acc,
                    "altitude": alt,
                    "speed": speed,
                    "ts": ts,
                    "content": contentJson
                ])
            }
            
            do {
                _ = try await apiClient.sendTelemetry([
                    "room_logs": roomLogs,
                    "is_offline": 1
                ])
                eventLogger.markAsSent(ids: locationEvents.map { $0.id })
            } catch {
                print("Error enviando room_logs de ubicación offline: \(error)")
            }
        }
        
        // 2. Procesar eventos institucionales (sos_triggered, geofence_enter/exit, etc.)
        if !institutionalEvents.isEmpty {
            let eventsPayload: [[String: Any]] = institutionalEvents.map { $0.asDictionary }
            do {
                let success = try await apiClient.sendInstitutionEvents(eventsPayload)
                if success {
                    eventLogger.markAsSent(ids: institutionalEvents.map { $0.id })
                }
            } catch {
                print("Error enviando eventos institucionales offline: \(error)")
            }
        }
    }
    
    func flushEvents() {
        Task {
            await flushEvents()
        }
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