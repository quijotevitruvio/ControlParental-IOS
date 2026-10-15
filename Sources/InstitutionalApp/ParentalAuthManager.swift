import Foundation
import Combine
import CryptoKit

final class ParentalAuthManager: ObservableObject {
    static let shared = ParentalAuthManager()
    
    private let pinKey = "parental_pin_hash_v1"
    
    @Published var isPinSet: Bool = false
    @Published var isUnlocked: Bool = false
    
    private init() {
        checkPinStatus()
    }
    
    func checkPinStatus() {
        let stored = UserDefaults.standard.string(forKey: pinKey)
        isPinSet = (stored != nil && !stored!.isEmpty)
        // Si no hay PIN configurado, requiere configurarlo primero (isUnlocked = false)
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
    
    func lock() {
        if isPinSet {
            isUnlocked = false
        }
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
