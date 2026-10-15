//
//  SettingsView.swift
//  InstitutionalApp
//  Configuración de la app institucional.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var telemetry = TelemetryManager.shared
    @StateObject private var eventLogger = EventLogger.shared
    @StateObject private var callManager = CallBlockerManager.shared
    @StateObject private var parentalAuth = ParentalAuthManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    
    @State private var showingServerEdit = false
    @State private var serverEditInput = ""
    @State private var showingClearAlert = false
    @State private var showingChangePin = false
    @State private var showingCallBlocker = false
    @State private var showingWizard = false
    
    // Estados para cambio de clave
    @State private var currentPinInput = ""
    @State private var newPinInput = ""
    @State private var pinChangeError: String? = nil
    @State private var pinChangeSuccess = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Servidor")) {
                    HStack {
                        Text("Servidor Corporativo")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("En línea")
                                .foregroundColor(.green)
                                .fontWeight(.medium)
                        }
                    }
                    .contentShape(Rectangle())
                    .onLongPressGesture {
                        serverEditInput = configManager.serverBase
                        showingServerEdit = true
                    }
                    
                    HStack {
                        Text("Seguridad")
                        Spacer()
                        Text("Conexión Cifrada SSL 🔒")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Vinculación de Dispositivo")) {
                    HStack {
                        Text("Estado")
                        Spacer()
                        if !configManager.deviceToken.isEmpty {
                            Text("Vinculado ✅")
                                .foregroundColor(.green)
                        } else {
                            Text("No vinculado ⚠️")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    if !configManager.deviceToken.isEmpty {
                        HStack {
                            Text("Token")
                            Spacer()
                            Text(String(configManager.deviceToken.prefix(12)) + "...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button("Vincular / Re-enrolar con Panel") {
                        Task {
                            _ = try? await APIClient.shared.enrollDevice()
                        }
                    }
                }
                
                Section(header: Text("Seguridad Parental")) {
                    HStack {
                        Text("Clave de Bloqueo")
                        Spacer()
                        Text(parentalAuth.isPinSet ? "Configurada ✅" : "Sin configurar ⚠️")
                            .foregroundColor(parentalAuth.isPinSet ? .green : .orange)
                    }
                    
                    Button("Cambiar Clave PIN") {
                        currentPinInput = ""
                        newPinInput = ""
                        pinChangeError = nil
                        pinChangeSuccess = false
                        showingChangePin = true
                    }
                    .foregroundColor(.blue)
                    
                    Button("Ver Guía de Configuración Inicial") {
                        showingWizard = true
                    }
                    .foregroundColor(.blue)
                    
                    Button("Bloquear App Ahora") {
                        parentalAuth.lock()
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("Filtro y Bloqueo de Llamadas")) {
                    Button(action: { showingCallBlocker = true }) {
                        HStack {
                            Label("Lista Negra de Números", systemImage: "phone.down.waves.left.and.right")
                            Spacer()
                            Text("\(callManager.blockedNumbers.count)")
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
                
                Section(header: Text("Organización")) {
                    HStack {
                        Text("Organización ID")
                        Spacer()
                        Text("\(ConfigManager.shared.orgId)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Caso ID")
                        Spacer()
                        Text("\(ConfigManager.shared.caseId)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Gestionado por MDM")
                        Spacer()
                        Image(systemName: ConfigManager.shared.isManaged ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(ConfigManager.shared.isManaged ? .green : .red)
                    }
                }
                
                Section(header: Text("Actualizaciones de la App")) {
                    HStack {
                        Text("Versión Instalada")
                        Spacer()
                        Text("Build \(updateManager.currentBuildNumber)")
                            .foregroundColor(.secondary)
                    }
                    
                    if updateManager.isUpdateAvailable {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("¡Nueva Versión Disponible!")
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                Text(updateManager.latestVersionName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Actualizar") {
                                updateManager.triggerUpdate()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                        }
                    } else {
                        Button("Buscar Actualizaciones en GitHub") {
                            updateManager.checkForUpdates()
                        }
                    }
                }
                
                Section(header: Text("Telemetría")) {
                    Button("Enviar telemetría ahora") {
                        Task { await TelemetryManager.shared.flushEvents() }
                    }
                    
                    HStack {
                        Text("Eventos pendientes")
                        Spacer()
                        Text("\(EventLogger.shared.pendingCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    if let lastSent = telemetry.lastSent {
                        HStack {
                            Text("Último envío")
                            Spacer()
                            Text(lastSent, style: .time)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showingClearAlert = true
                    } label: {
                        Text("Borrar todos los datos locales")
                    }
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCallBlocker) {
                CallBlockerView()
            }
            .sheet(isPresented: $showingChangePin) {
                NavigationView {
                    Form {
                        Section(header: Text("Clave Actual")) {
                            SecureField("4 dígitos actuales", text: $currentPinInput)
                                .keyboardType(.numberPad)
                        }
                        
                        Section(header: Text("Nueva Clave")) {
                            SecureField("4 dígitos nuevos", text: $newPinInput)
                                .keyboardType(.numberPad)
                        }
                        
                        if let error = pinChangeError {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        if pinChangeSuccess {
                            Text("¡Clave actualizada correctamente! ✅")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        
                        Button("Actualizar Clave") {
                            pinChangeError = nil
                            guard newPinInput.count == 4, newPinInput.allSatisfy({ $0.isNumber }) else {
                                pinChangeError = "La nueva clave debe tener 4 dígitos"
                                return
                            }
                            if parentalAuth.changePin(currentPin: currentPinInput, newPin: newPinInput) {
                                pinChangeSuccess = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    showingChangePin = false
                                }
                            } else {
                                pinChangeError = "La clave actual es incorrecta"
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(currentPinInput.count != 4 || newPinInput.count != 4)
                    }
                    .navigationTitle("Cambiar Clave")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Cerrar") { showingChangePin = false }
                        }
                    }
                }
            }
            .alert("¿Borrar todos los datos?", isPresented: $showingClearAlert) {
                Button("Cancelar", role: .cancel) { }
                Button("Borrar", role: .destructive) {
                    EventLogger.shared.clearAll()
                    UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
                }
            }
            .sheet(isPresented: $showingServerEdit) {
                NavigationView {
                    Form {
                        Section(header: Text("Configuración de Servidor")) {
                            SecureField("URL Servidor", text: $serverEditInput)
                                .textContentType(.URL)
                                .autocapitalization(.none)
                            
                            Button("Guardar Servidor") {
                                if !serverEditInput.isEmpty {
                                    configManager.serverBase = serverEditInput
                                    UserDefaults.standard.set(serverEditInput, forKey: "server_base")
                                }
                                showingServerEdit = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .navigationTitle("Ajuste de Servidor")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancelar") { showingServerEdit = false }
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingWizard) {
                OnboardingWizardView(isCompleted: $showingWizard)
            }
        }
    }
}