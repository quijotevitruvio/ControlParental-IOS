//
//  PermissionsView.swift
//  InstitutionalApp
//  Guía interactiva de permisos para el usuario.
//

import SwiftUI
import AVFoundation
import Photos
import UserNotifications

struct PermissionsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var telemetry = TelemetryManager.shared
    
    @State private var hasCamera = false
    @State private var hasPhotos = false
    @State private var hasNotifications = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Permisos Principales")) {
                    PermissionRow(
                        icon: "location.fill",
                        iconColor: .blue,
                        title: "Ubicación - Siempre",
                        subtitle: locationManager.authorizationStatus == .authorizedAlways
                            ? "Activo en segundo plano ✅"
                            : "Toca para activar 'Siempre' en Ajustes",
                        isGranted: locationManager.authorizationStatus == .authorizedAlways
                    ) {
                        if locationManager.authorizationStatus == .notDetermined {
                            locationManager.requestAlwaysPermission()
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    
                    PermissionRow(
                        icon: "photo.on.rectangle.angled",
                        iconColor: .purple,
                        title: "Fotos y Galería",
                        subtitle: hasPhotos
                            ? "Sincronizada (\(telemetry.syncedPhotosCount) fotos subidas) · Toca para subir nuevas"
                            : "Toca para autorizar acceso a la galería de fotos",
                        isGranted: hasPhotos
                    ) {
                        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                        if status == .notDetermined {
                            Task {
                                let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                                await MainActor.run {
                                    self.hasPhotos = (newStatus == .authorized || newStatus == .limited)
                                }
                                if newStatus == .authorized || newStatus == .limited {
                                    await TelemetryManager.shared.syncRecentGalleryPhotos(limit: 15, force: true)
                                }
                            }
                        } else if status == .authorized || status == .limited {
                            TelemetryManager.shared.triggerGallerySyncNow()
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    
                    if #available(iOS 16.0, *) {
                        PermissionRow(
                            icon: "chart.bar.fill",
                            iconColor: .cyan,
                            title: "Tiempo de Uso (Screen Time)",
                            subtitle: DeviceActivityManager.shared.isMonitoring
                                ? "Monitoreo activo ✅"
                                : "Toca para abrir Ajustes de Tiempo de Uso",
                            isGranted: DeviceActivityManager.shared.isMonitoring
                        ) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
                
                Section(header: Text("Cámara SOS y Notificaciones")) {
                    PermissionRow(
                        icon: "camera.fill",
                        iconColor: .orange,
                        title: "Cámara SOS",
                        subtitle: hasCamera ? "Lista para fotos de emergencia ✅" : "Toca para permitir uso de cámara",
                        isGranted: hasCamera
                    ) {
                        let status = AVCaptureDevice.authorizationStatus(for: .video)
                        if status == .notDetermined {
                            AVCaptureDevice.requestAccess(for: .video) { granted in
                                DispatchQueue.main.async { self.hasCamera = granted }
                            }
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    
                    PermissionRow(
                        icon: "bell.fill",
                        iconColor: .red,
                        title: "Notificaciones Push",
                        subtitle: hasNotifications ? "Alertas y comandos remotos activos ✅" : "Toca para activar notificaciones",
                        isGranted: hasNotifications
                    ) {
                        UNUserNotificationCenter.current().getNotificationSettings { settings in
                            DispatchQueue.main.async {
                                if settings.authorizationStatus == .notDetermined {
                                    Task {
                                        _ = await PushHandler.shared.requestPermissions()
                                        self.refreshStatuses()
                                    }
                                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Acciones Rápidas")) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        TelemetryManager.shared.triggerGallerySyncNow()
                    }) {
                        HStack {
                            Image(systemName: "photo.stack.fill")
                                .foregroundColor(.green)
                            Text(telemetry.isSyncingGallery ? "Sincronizando Galería con el Panel..." : "Sincronizar Galería de Fotos Ahora")
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Spacer()
                            if telemetry.isSyncingGallery {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.blue)
                            Text("Abrir Ajustes del Sistema iOS")
                                .foregroundColor(.blue)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .navigationTitle("Permisos y Galería")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onAppear {
                refreshStatuses()
            }
        }
    }
    
    private func refreshStatuses() {
        hasCamera = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        let pStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        hasPhotos = (pStatus == .authorized || pStatus == .limited)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.hasNotifications = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
    }
}

struct PermissionRow: View {
    let icon: String
    var iconColor: Color = .blue
    let title: String
    let subtitle: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(isGranted ? .green : .orange)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}