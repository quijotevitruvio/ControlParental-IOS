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
    
    @State private var serverBase = ""
    @State private var showingClearAlert = false
    @State private var showingChangePin = false
    @State private var showingCallBlocker = false
    
    // Estados para cambio de clave
    @State private var currentPinInput = ""
    @State private var newPinInput = ""
    @State private var pinChangeError: String? = nil
    @State private var pinChangeSuccess = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Servidor")) {
                    TextField("URL Base", text: $serverBase)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .onAppear { serverBase = configManager.serverBase }
                    
                    Button("Guardar") {
                        configManager.serverBase = serverBase
                        UserDefaults.standard.set(serverBase, forKey: "server_base")
                    }
                    .buttonStyle(.borderedProminent)
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
                    
                    if parentalAuth.isBiometricsAvailable {
                        Toggle(isOn: Binding(
                            get: { parentalAuth.isBiometricsEnabled },
                            set: { parentalAuth.setBiometricsEnabled($0) }
                        )) {
                            Label(parentalAuth.biometryTitle, systemImage: parentalAuth.biometryIconName)
                        }
                    }
                    
                    Button("Cambiar Clave PIN") {
                        currentPinInput = ""
                        newPinInput = ""
                        pinChangeError = nil
                        pinChangeSuccess = false
                        showingChangePin = true
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
        }
    }
}