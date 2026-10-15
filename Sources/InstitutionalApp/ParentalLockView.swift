import SwiftUI
import UIKit

struct ParentalLockView: View {
    @ObservedObject private var auth = ParentalAuthManager.shared
    
    @State private var pin: String = ""
    @State private var confirmPin: String = ""
    @State private var isConfirming: Bool = false
    @State private var errorMessage: String? = nil
    @State private var shakeOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                
                // Icono decorativo
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: auth.isPinSet ? "lock.shield.fill" : "key.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.blue)
                }
                .padding(.bottom, 12)
                
                // Título y Subtítulo
                VStack(spacing: 6) {
                    Text(titleText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 16)
                
                // Indicador de 4 dígitos (con animación shake)
                HStack(spacing: 18) {
                    ForEach(0..<4) { index in
                        Circle()
                            .fill(index < currentInput.count ? Color.blue : Color.secondary.opacity(0.25))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .offset(x: shakeOffset)
                .padding(.bottom, 10)
                
                // Mensaje de Error
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .frame(height: 20)
                } else {
                    Text(" ")
                        .font(.caption)
                        .frame(height: 20)
                }
                
                Spacer(minLength: 12)
                
                // Teclado Numérico
                numericKeypad
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
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
                : "Configura una clave de 4 dígitos para bloquear y administrar la app"
        } else {
            return "Introduce la clave de 4 dígitos para acceder al panel"
        }
    }
    
    private var numericKeypad: some View {
        VStack(spacing: 12) {
            ForEach(0..<3) { row in
                HStack(spacing: 20) {
                    ForEach(1..<4) { col in
                        let number = row * 3 + col
                        KeypadButton(text: "\(number)") {
                            keyPressed("\(number)")
                        }
                    }
                }
            }
            
            HStack(spacing: 20) {
                // Botón volver en modo confirmación
                if !auth.isPinSet && isConfirming {
                    KeypadButton(icon: "arrow.uturn.backward") {
                        isConfirming = false
                        confirmPin = ""
                        pin = ""
                        errorMessage = nil
                    }
                } else {
                    Color.clear
                        .frame(width: 66, height: 66)
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
            // Modo Configuración inicial
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
                            triggerErrorShake(message: "Las claves no coinciden. Intenta de nuevo.")
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
                        triggerErrorShake(message: "Clave incorrecta")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            pin = ""
                        }
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
    
    private func triggerErrorShake(message: String) {
        errorMessage = message
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        withAnimation(Animation.default.repeatCount(4, autoreverses: true).speed(4)) {
            shakeOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            shakeOffset = 0
        }
    }
}

// Botón de teclado con retroalimentación háptica y estilo visual al pulsar
private struct KeypadButton: View {
    var text: String? = nil
    var icon: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 66, height: 66)
                
                if let text = text {
                    Text(text)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(.primary)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(KeypadPressStyle())
    }
}

private struct KeypadPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
