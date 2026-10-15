//
//  ConfigManager.swift
//  InstitutionalApp
//
//  Lee configuración desde ManagedAppConfiguration (MDM).
//  Escucha cambios en tiempo real.
//

import Foundation
import Combine

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var serverBase: String = "https://elojodeja.trescerbero.com"
    @Published var orgId: Int = 0
    @Published var caseId: Int = 0
    @Published var riskThresholds: [String: Double] = [:]
    @Published var geofences: [GeofenceConfig] = []
    @Published var apnsTopic: String = ""
    @Published var isManaged = false
    
    private var cancellables = Set<AnyCancellable>()
    
    struct GeofenceConfig: Codable, Identifiable {
        let id: String
        let latitude: Double
        let longitude: Double
        let radiusMeters: Double
        let name: String?
    }
    
    private init() {
        loadFromManagedConfig()
        observeManagedConfigChanges()
    }
    
    private func loadFromManagedConfig() {
        guard let dict = UserDefaults.standard.dictionary(forKey: "ManagedAppConfiguration") as? [String: Any] else {
            // Fallback a defaults locales
            loadDefaults()
            return
        }
        
        parseManagedConfig(dict)
        isManaged = true
    }
    
    private func loadDefaults() {
        serverBase = UserDefaults.standard.string(forKey: "server_base") ?? "https://elojodeja.trescerbero.com"
        orgId = UserDefaults.standard.integer(forKey: "org_id")
        caseId = UserDefaults.standard.integer(forKey: "case_id")
        apnsTopic = UserDefaults.standard.string(forKey: "apns_topic") ?? ""
    }
    
    private func parseManagedConfig(_ dict: [String: Any]) {
        if let base = dict["server_base"] as? String, !base.isEmpty {
            serverBase = base
            UserDefaults.standard.set(base, forKey: "server_base")
        }
        
        if let org = dict["org_id"] as? Int {
            orgId = org
            UserDefaults.standard.set(org, forKey: "org_id")
        }
        
        if let caseId = dict["case_id"] as? Int {
            self.caseId = caseId
            UserDefaults.standard.set(caseId, forKey: "case_id")
        }
        
        if let topic = dict["apns_topic"] as? String {
            apnsTopic = topic
            UserDefaults.standard.set(topic, forKey: "apns_topic")
        }
        
        if let thresholds = dict["risk_thresholds"] as? [String: Double] {
            riskThresholds = thresholds
        }
        
        if let geofencesArray = dict["geofences"] as? [[String: Any]] {
            geofences = geofencesArray.compactMap { dict in
                guard let id = dict["id"] as? String,
                      let lat = dict["latitude"] as? Double,
                      let lng = dict["longitude"] as? Double,
                      let radius = dict["radius_meters"] as? Double else { return nil }
                return GeofenceConfig(
                    id: id,
                    latitude: lat,
                    longitude: lng,
                    radiusMeters: radius,
                    name: dict["name"] as? String
                )
            }
        }
    }
    
    private func observeManagedConfigChanges() {
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.loadFromManagedConfig()
            }
            .store(in: &cancellables)
    }
    
    func reloadFromMDM() {
        loadFromManagedConfig()
    }
    
    var baseURL: URL {
        URL(string: serverBase) ?? URL(string: "https://elojodeja.trescerbero.com")!
    }
    
    var apiBase: String {
        "\(serverBase)/elojodeja/api"
    }
}