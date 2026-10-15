//
//  DeviceActivityManager.swift
//  InstitutionalApp
//
//  Screen Time / DeviceActivity agregados (iOS 16+).
//  Requiere entitlement: com.apple.developer.device-activity
//

import Foundation
import DeviceActivity
import ManagedSettings
import Combine

extension DeviceActivityName {
    static let daily = DeviceActivityName("daily")
}

@available(iOS 16.0, *)
final class DeviceActivityManager: ObservableObject {
    static let shared = DeviceActivityManager()
    
    private let center = DeviceActivityCenter()
    private let store = ManagedSettingsStore()
    
    @Published var isMonitoring = false
    
    private init() {}
    
    func startMonitoring() {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        do {
            try center.startMonitoring(.daily, during: schedule)
            isMonitoring = true
        } catch {
            print("DeviceActivity monitoring failed: \(error)")
        }
    }
    
    func stopMonitoring() {
        center.stopMonitoring([.daily])
        isMonitoring = false
    }
    
    func fetchDailySummary() {
        // En iOS, el reporte detallado de Screen Time se procesa mediante una
        // DeviceActivityReportExtension para preservar la privacidad del usuario.
    }
    
    // Extrae resumen para telemetría
    func dailySummaryForTelemetry() -> [String: Any]? {
        guard isMonitoring else { return nil }
        return [
            "monitoring_active": true,
            "last_checked": ISO8601DateFormatter().string(from: Date())
        ]
    }
    
    // Bloqueo de apps por política (requiere supervisión MDM)
    func setAppRestrictions(blockedBundles: [String], allowedBundles: [String]? = nil) {
        // En iOS, las restricciones de aplicaciones se aplican a través de perfiles MDM
        // o mediante la extensión ShieldConfiguration de FamilyControls.
    }
    
    func clearRestrictions() {
        store.shield.applications = nil
    }
}