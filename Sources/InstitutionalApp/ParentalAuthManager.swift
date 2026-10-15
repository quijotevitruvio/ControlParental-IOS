import Foundation
import Combine
import CryptoKit
import LocalAuthentication

final class ParentalAuthManager: ObservableObject {
    static let shared = ParentalAuthManager()
    
    private let pinKey = "parental_pin_hash_v1"
    private let biometricsKey = "parental_biometrics_enabled"
    
    @Published var isPinSet: Bool = false
    @Published var isUnlocked: Bool = false
    @Published var isBiometricsEnabled: Bool = false
    
    private init() {
        checkPinStatus()
        isBiometricsEnabled = UserDefaults.standard.bool(forKey: biometricsKey)
    }
    
    func checkPinStatus() {
        let stored = UserDefaults.standard.string(forKey: pinKey)
        isPinSet = (stored != nil && !stored!.isEmpty)
        isUnlocked = false
    }
    
    func setPin(_ pin: String) -> Bool {
        guard pin.count == 4, pin.allSatisfy({ $0.isNumber }) else { return false }
        let hash = sha256(pin)
        UserDefaults.standard.set(hash, forKey: pinKey)
        isPinSet = true
        isUnlocked = true
        return true
    }
    
    func verifyPin(_ pin: String) -> Bool {
        guard let storedHash = UserDefaults.standard.string(forKey: pinKey) else {
            return false
        }
        let inputHash = sha256(pin)
        let isValid = (inputHash == storedHash)
        if isValid {
            isUnlocked = true
        }
        return isValid
    }
    
    func changePin(currentPin: String, newPin: String) -> Bool {
        guard verifyPin(currentPin) else { return false }
        return setPin(newPin)
    }
    
    func lock() {
        if isPinSet {
            isUnlocked = false
        }
    }
    
    func setBiometricsEnabled(_ enabled: Bool) {
        isBiometricsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: biometricsKey)
    }
    
    var isBiometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    var biometryIconName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        default:
            return "lock.circle"
        }
    }
    
    var biometryTitle: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "Biometría"
        }
    }
    
    @MainActor
    func authenticateWithBiometrics() async -> Bool {
        guard isPinSet && isBiometricsEnabled && isBiometricsAvailable else { return false }
        
        let context = LAContext()
        context.localizedCancelTitle = "Usar Clave PIN"
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Desbloquear Control Parental"
            )
            if success {
                self.isUnlocked = true
            }
            return success
        } catch {
            return false
        }
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
