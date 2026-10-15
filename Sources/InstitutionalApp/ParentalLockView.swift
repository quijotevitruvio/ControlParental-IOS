import SwiftUI

struct ParentalLockView: View {
    @ObservedObject private var auth = ParentalAuthManager.shared
    
    @State private var pin: String = ""
    @State private var confirmPin: String = ""
    @State private var isConfirming: Bool = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Icono y Títulos
                Image(systemName: auth.isPinSet ? "lock.shield.fill" : "key.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.accentColor)
                
                VStack(spacing: 8) {
                    Text(titleText)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                
                // Indicador de 4 dígitos
                HStack(spacing: 20) {
                    ForEach(0..<4) { index in
                        Circle()
                            .fill(index < currentInput.count ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 18, height: 18)
                    }
                }
                .padding(.vertical, 10)
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.semibold)
                } else {
                    Text(" ")
                        .font(.caption)
                }
                
                Spacer()
                
                // Teclado Numérico
                numericKeypad
                    .padding(.horizontal, 40)
                    .padding(.bottom, 30)
            }
        }
    }
    
    private var currentInput: String {
        isConfirming ? confirmPin : pin
    }
    
    private var titleText: String {
        if !auth.isPinSet {
            return isConfirming ? "Confirmar Clave" : "Crear Clave Parental"
        } else {
            return "App Bloqueada"
        }
    }
    
    private var subtitleText: String {
        if !auth.isPinSet {
            return isConfirming
                ? "Introduce de nuevo los 4 dígitos para verificarla"
                : "Configura una clave de 4 dígitos (distinta a la de tu iPhone) para bloquear y administrar la app"
        } else {
            return "Introduce la clave de 4 dígitos para acceder al panel de supervisión"
        }
    }
    
    private var numericKeypad: some View {
        VStack(spacing: 16) {
            ForEach(0..<3) { row in
                HStack(spacing: 24) {
                    ForEach(1..<4) { col in
                        let number = row * 3 + col
                        KeypadButton(text: "\(number)") {
                            keyPressed("\(number)")
                        }
                    }
                }
            }
            
            HStack(spacing: 24) {
                // Botón vacío o cancelar
                if !auth.isPinSet && isConfirming {
                    KeypadButton(icon: "arrow.uturn.backward") {
                        isConfirming = false
                        confirmPin = ""
                        pin = ""
                        errorMessage = nil
                    }
                } else {
                    Color.clear
                        .frame(width: 75, height: 75)
                }
                
                KeypadButton(text: "0") {
                    keyPressed("0")
                }
                
                KeypadButton(icon: "delete.left.fill") {
                    deletePressed()
                }
            }
        }
    }
    
    private func keyPressed(_ digit: String) {
        errorMessage = nil
        
        if !auth.isPinSet {
            // Modo Configuración
            if !isConfirming {
                if pin.count < 4 {
                    pin.append(digit)
                    if pin.count == 4 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            isConfirming = true
                        }
                    }
                }
            } else {
                if confirmPin.count < 4 {
                    confirmPin.append(digit)
                    if confirmPin.count == 4 {
                        if confirmPin == pin {
                            _ = auth.setPin(pin)
                        } else {
                            errorMessage = "Las claves no coinciden. Intenta de nuevo."
                            confirmPin = ""
                            pin = ""
                            isConfirming = false
                        }
                    }
                }
            }
        } else {
            // Modo Desbloqueo
            if pin.count < 4 {
                pin.append(digit)
                if pin.count == 4 {
                    let valid = auth.verifyPin(pin)
                    if !valid {
                        errorMessage = "Clave incorrecta"
                        pin = ""
                    }
                }
            }
        }
    }
    
    private func deletePressed() {
        errorMessage = nil
        if isConfirming {
            if !confirmPin.isEmpty { confirmPin.removeLast() }
        } else {
            if !pin.isEmpty { pin.removeLast() }
        }
    }
}

private struct KeypadButton: View {
    var text: String? = nil
    var icon: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 75, height: 75)
                
                if let text = text {
                    Text(text)
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
