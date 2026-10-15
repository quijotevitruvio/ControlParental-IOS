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
    
    @State private var serverBase = ""
    @State private var showingClearAlert = false
    
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
                    
                    HStack {
                        Text("Último envío")
                        Spacer()
                        Text(TelemetryManager.shared.lastSent?.relativeString ?? "Nunca")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Diagnóstico")) {
                    Button("Ver logs de envío") {
                        // Navegar a logs
                    }
                    
                    Button("Exportar diagnóstico") {
                        // Exportar logs
                    }
                    
                    Button("Probar conexión") {
                        Task {
                            do {
                                let ok = try await APIClient.shared.testConnection()
                                // Mostrar alerta
                            } catch {
                                // Mostrar error
                            }
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