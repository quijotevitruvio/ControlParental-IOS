//
//  DeviceActivityManager.swift
//  InstitutionalApp
//
//  Screen Time / DeviceActivity agregados (iOS 16+).
//  Requiere entitlement: com.apple.developer.device-activity
//

import Foundation
import Combine

@available(iOS 16.0, *)
final class DeviceActivityManager: ObservableObject {
    static let shared = DeviceActivityManager()
    
    @Published var isMonitoring = false
    
    private init() {}
    
    func startMonitoring() {
        // En instalaciones personales/sideloading no se cuenta con el entitlement com.apple.developer.family-controls.
        // Se desactiva de forma segura para no provocar terminación forzada (crash) de la aplicación.
        print("DeviceActivity: Screen Time solo disponible con perfil MDM empresarial.")
        isMonitoring = false
    }
    
    func stopMonitoring() {
        isMonitoring = false
    }
    
    func fetchDailySummary() {}
    
    func dailySummaryForTelemetry() -> [String: Any]? {
        return nil
    }
    
    func setAppRestrictions(blockedBundles: [String], allowedBundles: [String]? = nil) {}
    
    func clearRestrictions() {}
}