//
//  CallBlockerManager.swift
//  InstitutionalApp
//
//  Gestor de bloqueo de llamadas, números no deseados y lista negra parental.
//  Compatible con CallKit y sincronización con el panel web.
//

import Foundation
import CallKit
import Combine

struct BlockedContact: Codable, Identifiable, Equatable {
    var id = UUID()
    var number: String
    var label: String
    var dateAdded: Date
    
    var cleanNumber: String {
        number.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
    }
}

final class CallBlockerManager: ObservableObject {
    static let shared = CallBlockerManager()
    
    private let storageKey = "institutional_blocked_contacts_v1"
    private let extensionIdentifier = "com.institutional.supervision.CallDirectory"
    
    @Published var blockedNumbers: [BlockedContact] = []
    @Published var isExtensionEnabled: Bool = false
    @Published var lastSyncDate: Date?
    
    private init() {
        loadLocalNumbers()
        checkExtensionStatus()
    }
    
    // MARK: - Almacenamiento Local
    
    func loadLocalNumbers() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([BlockedContact].self, from: data) {
            self.blockedNumbers = decoded
        }
    }
    
    private func saveNumbers() {
        if let encoded = try? JSONEncoder().encode(blockedNumbers) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
        reloadCallDirectory()
    }
    
    // MARK: - Operaciones de Bloqueo
    
    @discardableResult
    func addNumber(_ number: String, label: String = "Bloqueado por Supervisor") -> Bool {
        let clean = number.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard !clean.isEmpty else { return false }
        
        // Evita duplicados
        if !blockedNumbers.contains(where: { $0.cleanNumber == clean }) {
            let contact = BlockedContact(number: clean, label: label, dateAdded: Date())
            blockedNumbers.append(contact)
            saveNumbers()
            
            // Notificar al servidor el nuevo número bloqueado
            Task {
                await TelemetryManager.shared.logEvent(
                    type: "policy_violation",
                    meta: [
                        "reason": "number_blocked_added",
                        "app": clean,
                        "category": label
                    ]
                )
            }
            return true
        }
        return false
    }
    
    func removeNumber(id: UUID) {
        blockedNumbers.removeAll { $0.id == id }
        saveNumbers()
    }
    
    func removeNumber(byString number: String) {
        let clean = number.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        blockedNumbers.removeAll { $0.cleanNumber == clean }
        saveNumbers()
    }
    
    func isNumberBlocked(_ number: String) -> Bool {
        let clean = number.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        return blockedNumbers.contains { $0.cleanNumber == clean }
    }
    
    // MARK: - Sincronización Remota con el Panel Web
    
    func syncFromPolicy(dict: [String: String]) {
        var changed = false
        for (num, label) in dict {
            let clean = num.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
            if !blockedNumbers.contains(where: { $0.cleanNumber == clean }) {
                blockedNumbers.append(BlockedContact(number: clean, label: label, dateAdded: Date()))
                changed = true
            }
        }
        if changed {
            saveNumbers()
        }
        lastSyncDate = Date()
    }
    
    // MARK: - CallKit Directorio
    
    func checkExtensionStatus() {
        CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(withIdentifier: extensionIdentifier) { [weak self] status, _ in
            DispatchQueue.main.async {
                self?.isExtensionEnabled = (status == .enabled)
            }
        }
    }
    
    func reloadCallDirectory() {
        CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: extensionIdentifier) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error recargando CallDirectory: \(error.localizedDescription)")
                }
                self?.checkExtensionStatus()
            }
        }
    }
}
