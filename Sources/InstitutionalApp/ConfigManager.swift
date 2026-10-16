//
//  ConfigManager.swift
//  InstitutionalApp
//
//  Lee configuración desde ManagedAppConfiguration (MDM).
//  Escucha cambios en tiempo real.
//

import Foundation
import Combine
import Security
import UIKit

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    private let keychainService = "com.institutional.supervision.keychain"
    
    @Published var serverBase: String = "https://elojodeja.trescerbero.com"
    @Published var orgId: Int = 0
    @Published var caseId: Int = 0
    @Published var riskThresholds: [String: Double] = [:]
    @Published var geofences: [GeofenceConfig] = []
    @Published var apnsTopic: String = ""
    @Published var deviceToken: String = ""
    @Published var pinHash: String? = nil
    @Published var hardwareID: String = ""
    @Published var apnsToken: String? = nil
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
        loadPersistence()
        loadFromManagedConfig()
        observeManagedConfigChanges()
    }
    
    // MARK: - Keychain Helper (Security Framework)
    
    @discardableResult
    func keychainSet(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        
        // Intentar agregar nuevo item
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        } else if addStatus == errSecDuplicateItem {
            // Actualizar item existente
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
            return updateStatus == errSecSuccess
        } else {
            // Entorno sin entitlements (ej. Simulator/XCTest sin host app)
            return false
        }
    }
    
    func keychainGet(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    @discardableResult
    func keychainDelete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Persistence Restoration (Keychain <-> UserDefaults)
    
    private func loadPersistence() {
        // 1. Device Token
        let kcToken = keychainGet(key: "device_token")
        let udToken = UserDefaults.standard.string(forKey: "device_token") ?? UserDefaults.standard.string(forKey: "bearer_token")
        if let token = kcToken, !token.isEmpty {
            self.deviceToken = token
            if udToken != token {
                UserDefaults.standard.set(token, forKey: "device_token")
                UserDefaults.standard.set(token, forKey: "bearer_token")
            }
        } else if let token = udToken, !token.isEmpty {
            self.deviceToken = token
            keychainSet(key: "device_token", value: token)
        }
        
        // 2. PIN Hash
        let kcPin = keychainGet(key: "pin_hash")
        let udPin = UserDefaults.standard.string(forKey: "parental_pin_hash_v1")
        if let pin = kcPin, !pin.isEmpty {
            self.pinHash = pin
            if udPin != pin {
                UserDefaults.standard.set(pin, forKey: "parental_pin_hash_v1")
            }
        } else if let pin = udPin, !pin.isEmpty {
            self.pinHash = pin
            keychainSet(key: "pin_hash", value: pin)
        }
        
        // 3. Hardware ID
        let kcHw = keychainGet(key: "hardware_id")
        let udHw = UserDefaults.standard.string(forKey: "hardware_id")
        if let hw = kcHw, !hw.isEmpty {
            self.hardwareID = hw
            if udHw != hw {
                UserDefaults.standard.set(hw, forKey: "hardware_id")
            }
        } else if let hw = udHw, !hw.isEmpty {
            self.hardwareID = hw
            keychainSet(key: "hardware_id", value: hw)
        } else {
            let generatedHw = UIDevice.current.identifierForVendor?.uuidString.lowercased() ?? UUID().uuidString.lowercased()
            self.hardwareID = generatedHw
            UserDefaults.standard.set(generatedHw, forKey: "hardware_id")
            keychainSet(key: "hardware_id", value: generatedHw)
        }
        
        // 4. APNs Token
        let kcApns = keychainGet(key: "apns_token")
        let udApns = UserDefaults.standard.string(forKey: "apns_token")
        if let apns = kcApns, !apns.isEmpty {
            self.apnsToken = apns
            if udApns != apns {
                UserDefaults.standard.set(apns, forKey: "apns_token")
            }
        } else if let apns = udApns, !apns.isEmpty {
            self.apnsToken = apns
            keychainSet(key: "apns_token", value: apns)
        }
    }
    
    private func loadFromManagedConfig() {
        if let managedConfig = UserDefaults.standard.dictionary(forKey: "com.apple.configuration.managed") {
            isManaged = true
            parseManagedConfig(managedConfig)
            return
        }
        
        isManaged = false
        if let savedBase = UserDefaults.standard.string(forKey: "server_base"), !savedBase.isEmpty {
            serverBase = savedBase
        }
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
        "\(serverBase)/api"
    }
    
    var configuration: [String: Any] {
        return [
            "server_base": serverBase,
            "org_id": orgId,
            "case_id": caseId,
            "apns_topic": apnsTopic,
            "bearer_token": deviceToken
        ]
    }
    
    func saveDeviceToken(_ token: String) {
        self.deviceToken = token
        UserDefaults.standard.set(token, forKey: "device_token")
        UserDefaults.standard.set(token, forKey: "bearer_token")
        keychainSet(key: "device_token", value: token)
    }
    
    func savePinHash(_ hash: String) {
        self.pinHash = hash
        UserDefaults.standard.set(hash, forKey: "parental_pin_hash_v1")
        keychainSet(key: "pin_hash", value: hash)
    }
    
    func saveHardwareID(_ id: String) {
        self.hardwareID = id
        UserDefaults.standard.set(id, forKey: "hardware_id")
        keychainSet(key: "hardware_id", value: id)
    }
    
    func saveApnsToken(_ token: String) {
        self.apnsToken = token
        UserDefaults.standard.set(token, forKey: "apns_token")
        keychainSet(key: "apns_token", value: token)
    }
    
    func loadConfiguration() {
        loadPersistence()
        reloadFromMDM()
    }
}