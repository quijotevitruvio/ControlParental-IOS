//
//  CallDirectoryHandler.swift
//  CallDirectoryExtension
//
//  CallKit Call Directory Extension para bloqueo automático de llamadas entrantes
//  en segundo plano según la política institucional.
//

import Foundation
import CallKit

final class CallDirectoryHandler: CXCallDirectoryProvider {
    
    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self
        
        if context.isIncremental {
            context.removeAllBlockingEntries()
        }
        
        addAllBlockingPhoneNumbers(to: context)
        context.completeRequest()
    }
    
    private func addAllBlockingPhoneNumbers(to context: CXCallDirectoryExtensionContext) {
        let suite = "group.com.institutional.supervision"
        let defaults = UserDefaults(suiteName: suite) ?? UserDefaults.standard
        
        // 1. Obtener lista de números bloqueados
        var rawNumbers: [String] = defaults.stringArray(forKey: "blocked_phone_numbers") ?? []
        
        // Fallback a almacenamiento codificado en JSON si la lista plana está vacía
        if rawNumbers.isEmpty,
           let data = defaults.data(forKey: "institutional_blocked_contacts_v1"),
           let contacts = try? JSONDecoder().decode([LocalBlockedContact].self, from: data) {
            rawNumbers = contacts.map { $0.cleanNumber }
        }
        
        // 2. Extraer dígitos, convertir a CXCallDirectoryPhoneNumber (Int64) y ordenar ascendentemente
        // CallKit exige ESTRICTAMENTE orden numérico ascendente sin duplicados.
        let phoneNumbers: [CXCallDirectoryPhoneNumber] = rawNumbers.compactMap { raw in
            let digits = raw.filter { $0.isNumber }
            guard !digits.isEmpty, let num = Int64(digits) else { return nil }
            return num
        }.sorted()
        
        var lastNumber: CXCallDirectoryPhoneNumber?
        for phoneNumber in phoneNumbers {
            if phoneNumber != lastNumber {
                context.addBlockingEntry(withNextSequentialPhoneNumber: phoneNumber)
                lastNumber = phoneNumber
            }
        }
    }
}

// Estructura auxiliar para decodificación interna sin dependencias
private struct LocalBlockedContact: Decodable {
    let number: String
    var cleanNumber: String {
        number.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        // En caso de fallo en la extensión
    }
}
