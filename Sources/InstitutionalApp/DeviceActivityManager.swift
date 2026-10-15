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

@available(iOS 16.0, *)
final class DeviceActivityManager: ObservableObject {
    static let shared = DeviceActivityManager()
    
    private let center = DeviceActivityCenter()
    private let store = ManagedSettingsStore()
    
    @Published var dailySummary: DeviceActivityReport?
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
            fetchDailySummary()
        } catch {
            print("DeviceActivity monitoring failed: \(error)")
        }
    }
    
    func stopMonitoring() {
        center.stopMonitoring(.daily)
        isMonitoring = false
    }
    
    func fetchDailySummary() {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let interval = DateInterval(start: startOfDay, end: endOfDay)
        
        let query = DeviceActivityReportQuery(
            deviceActivityName: .daily,
            filter: DeviceActivityFilter(
                segment: .init(
                    applications: nil,
                    categories: nil,
                    webDomains: nil
                ),
                users: nil,
                devices: nil
            ),
            aggregation: .init(
                totalActivityDuration: .sum,
                numberOfPickups: .sum,
                firstPickupTime: .min,
                lastPickupTime: .max
            )
        )
        
        let report = try? center.queryReport(for: query)
        DispatchQueue.main.async {
            self.dailySummary = report
        }
    }
    
    // Extrae resumen para telemetría
    func dailySummaryForTelemetry() -> [String: Any]? {
        guard let report = dailySummary else { return nil }
        
        var result: [String: Any] = [:]
        
        // Tiempo total
        if let total = report.totalActivityDuration {
            result["total_screen_time_minutes"] = Int(total / 60)
        }
        
        // Pickups
        if let pickups = report.numberOfPickups {
            result["pickups"] = pickups
        }
        
        // Top apps
        var topApps: [[String: Any]] = []
        for segment in report.segments {
            for app in segment.applications {
                if let bundle = app.application?.bundleIdentifier,
                   let name = app.application?.localizedDisplayName,
                   let duration = app.totalActivityDuration {
                    topApps.append([
                        "bundle_id": bundle,
                        "name": name,
                        "minutes": Int(duration / 60)
                    ])
                }
            }
        }
        result["top_apps"] = topApps.sorted { ($0["minutes"] as? Int ?? 0) > ($1["minutes"] as? Int ?? 0) }.prefix(10)
        
        // Categorías
        var categories: [[String: Any]] = []
        for segment in report.segments {
            for cat in segment.categories {
                if let name = cat.category?.localizedDisplayName,
                   let duration = cat.totalActivityDuration {
                    categories.append([
                        "category": name,
                        "minutes": Int(duration / 60)
                    ])
                }
            }
        }
        result["categories"] = categories
        
        return result
    }
    
    // Bloqueo de apps por política (requiere supervisión MDM)
    func setAppRestrictions(blockedBundles: [String], allowedBundles: [String]? = nil) {
        let config = ApplicationRestrictionsConfiguration()
        if !blockedBundles.isEmpty {
            config.blockedApplications = blockedBundles.compactMap { Application.Token(bundleIdentifier: $0) }
        }
        if let allowed = allowedBundles, !allowed.isEmpty {
            config.allowedApplications = allowed.compactMap { Application.Token(bundleIdentifier: $0) }
        }
        store.applicationRestrictions = config
    }
    
    func clearRestrictions() {
        store.applicationRestrictions = nil
    }
}