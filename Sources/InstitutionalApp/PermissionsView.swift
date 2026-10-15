//
//  PermissionsView.swift
//  InstitutionalApp
//  Guía de permisos para el usuario.
//

import SwiftUI

struct PermissionsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var locationManager = LocationManager.shared
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Permisos Obligatorios")) {
                    PermissionRow(
                        icon: "location.fill",
                        title: "Ubicación - Siempre",
                        subtitle: "Necesario para ubicación continua y geocercas",
                        isGranted: LocationManager.shared.authorizationStatus == .authorizedAlways
                    ) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    
                    if #available(iOS 16.0, *) {
                        HStack {
                            Image(systemName: "chart.bar.fill").foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Tiempo de Uso (Screen Time)")
                                Text("DeviceActivity para reportes agregados").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: DeviceActivityManager.shared.isMonitoring ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(DeviceActivityManager.shared.isMonitoring ? .green : .orange)
                        }
                    }
                }
                
                Section(header: Text("Permisos para SOS")) {
                    HStack {
                        Image(systemName: "camera.fill").foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("Cámara").font(.subheadline)
                            Text("Para botón SOS con foto").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
                
                HStack {
                    Image(systemName: "photo.fill").foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("Fotos / Galería").font(.subheadline)
                        Text("Para SOS con foto de galería").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
                }
                
                Section(header: Text("Notificaciones")) {
                    HStack {
                        Image(systemName: "bell.fill").foregroundColor(.red)
                        VStack(alignment: .leading) {
                            Text("Notificaciones Push")
                            Text("SOS, comandos silenciosos, alertas MDM").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
                }
                
                Section {
                    Text("La app funciona bajo supervisión MDM. Los permisos se configuran vía perfil MDM en Ajustes > General > Gestión de Dispositivos.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Permisos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline)
                Text("Toque para configurar").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isGranted ? .green : .orange)
                .onTapGesture { action() }
        }
    }
}