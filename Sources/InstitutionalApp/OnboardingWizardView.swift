//
//  OnboardingWizardView.swift
//  InstitutionalApp
//
//  Guía interactiva paso a paso para la configuración inicial de la app:
//  - Clave Parental de 4 dígitos
//  - Permiso de Ubicación "Siempre"
//  - Notificaciones
//  - Cámara SOS
//  - Activación de CallKit y Anti-Eliminación en iOS
//

import SwiftUI
import AVFoundation
import CoreLocation

struct OnboardingWizardView: View {
    @Binding var isCompleted: Bool
    
    @State private var currentStep: Int = 1
    private let totalSteps: Int = 6
    
    // Estados para el PIN
    @State private var pin: String = ""
    @State private var confirmPin: String = ""
    @State private var isConfirming: Bool = false
    @State private var pinError: String? = nil
    
    // Estados de permisos
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var hasNotificationPermission: Bool = false
    @State private var hasCameraPermission: Bool = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Barra de Progreso Superior
                headerProgress
                    .padding(.top, 16)
                    .padding(.horizontal, 24)
                
                Spacer()
                
                // Contenido del Paso Actual
                Group {
                    switch currentStep {
                    case 1:
                        stepWelcome
                    case 2:
                        stepSetPin
                    case 3:
                        stepLocation
                    case 4:
                        stepNotificationsAndCamera
                    case 5:
                        stepAppleProtections
                    case 6:
                        stepFinished
                    default:
                        EmptyView()
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                
                Spacer()
                
                // Botones de Navegación Inferior
                bottomNavigation
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            checkPermissions()
        }
    }
    
    private var headerProgress: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Configuración Inicial")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Text("Paso \(currentStep) de \(totalSteps)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            ProgressView(value: Double(currentStep), total: Double(totalSteps))
                .tint(.blue)
        }
    }
    
    // MARK: - Paso 1: Bienvenida
    
    private var stepWelcome: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 8) {
                Text("Bienvenido a Empresas")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Esta guía de pasos te ayudará a activar todos los permisos necesarios y proteger la app en 2 minutos.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "key.fill", color: .purple, title: "Clave Maestra", subtitle: "Bloqueo con PIN secreto solo para ti")
                FeatureRow(icon: "location.fill", color: .green, title: "GPS en Vivo", subtitle: "Rastreo continuo de bajo consumo")
                FeatureRow(icon: "phone.down.waves.left.and.right", color: .red, title: "Bloqueador de Llamadas", subtitle: "Rechazo de números no deseados con CallKit")
            }
            .padding(18)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding(.horizontal, 10)
        }
    }
    
    // MARK: - Paso 2: Crear Clave Parental
    
    private var stepSetPin: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundColor(.blue)
            
            VStack(spacing: 6) {
                Text(isConfirming ? "Confirma la Clave" : "Crea tu Clave Parental")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(isConfirming
                     ? "Vuelve a introducir los 4 dígitos para confirmar"
                     : "Define un PIN de 4 dígitos (distinto al código del iPhone) que solo tú conozcas")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            // Indicador de 4 puntos
            HStack(spacing: 18) {
                ForEach(0..<4) { index in
                    Circle()
                        .fill(index < currentPinInput.count ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.vertical, 8)
            
            if let err = pinError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fontWeight(.semibold)
            } else {
                Text(" ")
                    .font(.caption)
            }
            
            // Mini Teclado
            VStack(spacing: 12) {
                ForEach(0..<3) { row in
                    HStack(spacing: 24) {
                        ForEach(1..<4) { col in
                            let num = "\(row * 3 + col)"
                            WizardKeyButton(text: num) { pinKeyPressed(num) }
                        }
                    }
                }
                HStack(spacing: 24) {
                    if isConfirming {
                        WizardKeyButton(icon: "arrow.uturn.backward") {
                            isConfirming = false
                            confirmPin = ""
                            pin = ""
                            pinError = nil
                        }
                    } else {
                        Color.clear.frame(width: 65, height: 50)
                    }
                    WizardKeyButton(text: "0") { pinKeyPressed("0") }
                    WizardKeyButton(icon: "delete.left.fill") { pinDeletePressed() }
                }
            }
        }
    }
    
    private var currentPinInput: String {
        isConfirming ? confirmPin : pin
    }
    
    private func pinKeyPressed(_ digit: String) {
        pinError = nil
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
                        _ = ParentalAuthManager.shared.setPin(pin)
                        withAnimation {
                            currentStep = 3
                        }
                    } else {
                        pinError = "Las claves no coinciden. Intenta de nuevo."
                        pin = ""
                        confirmPin = ""
                        isConfirming = false
                    }
                }
            }
        }
    }
    
    private func pinDeletePressed() {
        pinError = nil
        if isConfirming {
            if !confirmPin.isEmpty { confirmPin.removeLast() }
        } else {
            if !pin.isEmpty { pin.removeLast() }
        }
    }
    
    // MARK: - Paso 3: Ubicación GPS "Siempre"
    
    private var stepLocation: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 90, height: 90)
                Image(systemName: "location.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 8) {
                Text("Rastreo GPS Continuo")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Para rastrear la posición en tiempo real aun con el iPhone bloqueado o la app minimizada, se requiere el permiso **Siempre**.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Estado:")
                        .fontWeight(.semibold)
                    Spacer()
                    if locationManager.authorizationStatus == .authorizedAlways {
                        Text("Activo 'Siempre' ✅")
                            .foregroundColor(.green)
                            .fontWeight(.bold)
                    } else if locationManager.authorizationStatus == .authorizedWhenInUse {
                        Text("En Uso ⚠️ (Pasar a 'Siempre')")
                            .foregroundColor(.orange)
                            .fontWeight(.bold)
                    } else {
                        Text("Sin solicitar ⏳")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.subheadline)
                
                Divider()
                
                Text("📌 **Importante:** Pulsa el botón de abajo. Si es la primera vez, elige *'Permitir al usar la app'*. Si ya lo diste, pulsa para abrir Ajustes y selecciona **'Siempre'**.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
            .padding(.horizontal, 10)
            
            if locationManager.authorizationStatus == .authorizedAlways {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title)
                            .foregroundColor(.green)
                        Text("¡Ubicación 'Siempre' Activa!")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(12)
                    
                    Button(action: {
                        withAnimation { currentStep = 4 }
                    }) {
                        HStack {
                            Text("Continuar al Siguiente Paso")
                                .fontWeight(.bold)
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(.horizontal, 10)
            } else if locationManager.authorizationStatus == .notDetermined {
                Button(action: {
                    LocationManager.shared.requestAlwaysPermission()
                }) {
                    HStack {
                        Image(systemName: "location.circle.fill")
                        Text("Solicitar Permiso de Ubicación")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.horizontal, 10)
            } else {
                // Está en authorizedWhenInUse o denegado
                VStack(spacing: 12) {
                    Button(action: {
                        LocationManager.shared.openSettings()
                    }) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                            Text("Abrir Ajustes del iPhone (Poner 'Siempre')")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    
                    Button(action: {
                        LocationManager.shared.requestAlwaysPermission()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reintentar Diálogo en Pantalla")
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 10)
            }
        }
    }
    
    // MARK: - Paso 4: Notificaciones y Cámara
    
    private var stepNotificationsAndCamera: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 90, height: 90)
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 8) {
                Text("Notificaciones y Cámara SOS")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Necesarias para recibir alertas de comandos remotos y capturar fotos en caso de emergencia SOS.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            VStack(spacing: 12) {
                // Fila Notificaciones
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.blue)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notificaciones Push")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Alertas y comandos silenciosos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        Task {
                            _ = await PushHandler.shared.requestPermissions()
                            checkPermissions()
                        }
                    }) {
                        Text(hasNotificationPermission ? "Activo ✅" : "Activar")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(hasNotificationPermission ? Color.green.opacity(0.15) : Color.blue)
                            .foregroundColor(hasNotificationPermission ? .green : .white)
                            .cornerRadius(8)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                
                // Fila Cámara
                HStack {
                    Image(systemName: "camera.fill")
                        .foregroundColor(.orange)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cámara SOS")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Captura de evidencia en pánico")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        AVCaptureDevice.requestAccess(for: .video) { granted in
                            DispatchQueue.main.async {
                                hasCameraPermission = granted
                            }
                        }
                    }) {
                        Text(hasCameraPermission ? "Activo ✅" : "Activar")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(hasCameraPermission ? Color.green.opacity(0.15) : Color.orange)
                            .foregroundColor(hasCameraPermission ? .green : .white)
                            .cornerRadius(8)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
            }
            .padding(.horizontal, 10)
        }
    }
    
    // MARK: - Paso 5: Protecciones Nativas de iOS
    
    private var stepAppleProtections: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "lock.laptopcomputer")
                    .font(.system(size: 38))
                    .foregroundColor(.purple)
            }
            
            VStack(spacing: 6) {
                Text("Protecciones de iOS")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Configuraciones recomendadas en los Ajustes del iPhone para máxima seguridad:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("1. Bloqueador de Llamadas (CallKit)", systemImage: "phone.down.waves.left.and.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("Ajustes ➔ Teléfono ➔ Bloqueo e ID de llamadas ➔ Activar **Empresas**.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Label("2. Evitar que eliminen la app", systemImage: "xmark.bin.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("Ajustes ➔ Tiempo de uso ➔ Restricciones ➔ Compras en iTunes y App Store ➔ **Eliminar apps: 'No permitir'**.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
            .padding(.horizontal, 10)
            
            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Abrir Ajustes de iOS")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 10)
        }
    }
    
    // MARK: - Paso 6: Listo
    
    private var stepFinished: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 54))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 8) {
                Text("¡Todo Configurado!")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("La aplicación está lista para funcionar en segundo plano y reportar al panel de control.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Clave Parental activa")
                }
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Ubicación y Telemetría configuradas")
                }
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Bloqueador de llamadas listo")
                }
            }
            .font(.subheadline)
            .padding(18)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
        }
    }
    
    // MARK: - Navegación Inferior
    
    private var bottomNavigation: some View {
        HStack {
            if currentStep > 1 && currentStep < 6 && currentStep != 2 {
                Button(action: {
                    withAnimation { currentStep -= 1 }
                }) {
                    Text("Anterior")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if currentStep == 1 {
                Button(action: {
                    withAnimation {
                        // Si ya tiene PIN salta al paso 3, si no al paso 2
                        currentStep = ParentalAuthManager.shared.isPinSet ? 3 : 2
                    }
                }) {
                    HStack {
                        Text("Comenzar Guía")
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            } else if currentStep == 2 {
                // En el paso 2 se avanza completando los 4 dígitos
                Text("Ingresa los 4 dígitos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if currentStep < 6 {
                Button(action: {
                    withAnimation { currentStep += 1 }
                }) {
                    HStack {
                        Text("Siguiente Paso")
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            } else {
                Button(action: {
                    UserDefaults.standard.set(true, forKey: "has_completed_onboarding_v1")
                    ParentalAuthManager.shared.isUnlocked = true
                    withAnimation {
                        isCompleted = true
                    }
                }) {
                    HStack {
                        Text("Ir al Panel de Control")
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private func checkPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.hasNotificationPermission = (settings.authorizationStatus == .authorized)
            }
        }
        hasCameraPermission = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
    }
}

// Botones auxiliares
private struct WizardKeyButton: View {
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
                    .frame(width: 65, height: 65)
                
                if let text = text {
                    Text(text)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(.primary)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(WizardKeypadPressStyle())
    }
}

private struct WizardKeypadPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
