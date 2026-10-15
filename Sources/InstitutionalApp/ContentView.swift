//
//  ContentView.swift
//  InstitutionalApp
//  Pantalla principal de la app institucional.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var telemetry = TelemetryManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var sosManager = SOSManager.shared
    @StateObject private var pushHandler = PushHandler.shared
    @StateObject private var parentalAuth = ParentalAuthManager.shared
    
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showingPermissions = false
    @State private var showingSettings = false
    
    var body: some View {
        ZStack {
            mainDashboard
                .blur(radius: parentalAuth.isUnlocked ? 0 : 15)
                .disabled(!parentalAuth.isUnlocked)
            
            if !parentalAuth.isUnlocked {
                ParentalLockView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                parentalAuth.lock()
            }
        }
        .onAppear {
            autoRequestPermissions()
        }
    }
    
    private var mainDashboard: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    connectionStatusCard
                    permissionsStatusCard
                    telemetryCard
                    locationCard
                    SOSButtonView()
                    lastSyncCard
                }
                .padding()
            }
            .navigationTitle("Institucional")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingPermissions = true }) {
                        Image(systemName: "shield.lefthalf.filled")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingPermissions) {
                PermissionsView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onAppear {
                if !TelemetryManager.shared.isUpdating { TelemetryManager.shared.start() }
                if LocationManager.shared.authorizationStatus == .authorizedAlways {
                    LocationManager.shared.startUpdating()
                }
            }
        }
    }
    
    private func autoRequestPermissions() {
        let hasRequested = UserDefaults.standard.bool(forKey: "has_auto_requested_permissions")
        if !hasRequested {
            UserDefaults.standard.set(true, forKey: "has_auto_requested_permissions")
            Task {
                // 1. Ubicación
                LocationManager.shared.requestAlwaysPermission()
                
                // 2. Notificaciones
                _ = await PushHandler.shared.requestPermissions()
                
                // 3. Cámara
                AVCaptureDevice.requestAccess(for: .video) { _ in }
            }
        }
    }
    
    var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Supervisión Institucional")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(ConfigManager.shared.isManaged ? "Gestionado por MDM" : "Modo manual")
                .font(.caption)
                .foregroundColor(ConfigManager.shared.isManaged ? .green : .orange)
        }
        .padding(.top)
    }
    
    var connectionStatusCard: some View {
        CardView {
            HStack {
                Circle()
                    .fill(NetworkMonitor.shared.isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(NetworkMonitor.shared.isConnected ? "Conectado" : "Sin conexión")
                        .font(.headline)
                    Text(NetworkMonitor.shared.connectionTypeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if TelemetryManager.shared.isSending {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
    }
    
    var permissionsStatusCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Permisos Requeridos")
                    .font(.headline)
                
                DashboardPermissionRow(
                    icon: "location.fill",
                    title: "Ubicación",
                    description: "Permiso \"Siempre\" para ubicación continua",
                    isGranted: LocationManager.shared.authorizationStatus == .authorizedAlways,
                    action: { LocationManager.shared.requestAlwaysPermission() }
                )
                
                DashboardPermissionRow(
                    icon: "camera.fill",
                    title: "Cámara",
                    description: "Para botón SOS con foto",
                    isGranted: true,
                    action: {}
                )
                
                DashboardPermissionRow(
                    icon: "photo.fill",
                    title: "Fotos",
                    description: "Para SOS con foto de galería",
                    isGranted: true,
                    action: {}
                )
                
                DashboardPermissionRow(
                    icon: "bell.fill",
                    title: "Notificaciones",
                    description: "Alertas SOS y comandos silenciosos",
                    isGranted: true,
                    action: { Task { _ = await PushHandler.shared.requestPermissions() } }
                )
                
                if #available(iOS 16.0, *) {
                    DashboardPermissionRow(
                        icon: "chart.bar.fill",
                        title: "Tiempo de Uso",
                        description: "Screen Time agregado (DeviceActivity)",
                        isGranted: DeviceActivityManager.shared.isMonitoring,
                        action: { DeviceActivityManager.shared.startMonitoring() }
                    )
                }
                
                Button(action: { }) {
                    Text("Gestionar Permisos")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
    
    var telemetryCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Telemetría")
                        .font(.headline)
                    Spacer()
                    ProgressView().scaleEffect(0.7)
                        .opacity(TelemetryManager.shared.isUpdating ? 1 : 0)
                }
                
                HStack(spacing: 20) {
                    StatItem(label: "Último envío", value: TelemetryManager.shared.lastSent?.relativeString ?? "Nunca")
                    StatItem(label: "Eventos pendientes", value: String(EventLogger.shared.pendingCount))
                }
                
                Button(action: { Task { await TelemetryManager.shared.flushEvents() } }) {
                    Text("Enviar Ahora")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
    
    var locationCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ubicación")
                        .font(.headline)
                    Spacer()
                    Circle()
                        .fill(LocationManager.shared.authorizationStatus == .authorizedAlways ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                }
                
                if let loc = LocationManager.shared.lastLocation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lat: \(loc.coordinate.latitude, specifier: "%.6f")")
                        Text("Lng: \(loc.coordinate.longitude, specifier: "%.6f")")
                        Text("Precisión: \(Int(loc.horizontalAccuracy))m")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    Text("Sin ubicación disponible")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Button("Actualizar") {
                        LocationManager.shared.startUpdating()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Geocercas") { }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
    
    var lastSyncCard: some View {
        CardView {
            HStack {
                VStack(alignment: .leading) {
                    Text("Última sincronización")
                        .font(.subheadline)
                    Text(TelemetryManager.shared.lastSent?.relativeString ?? "Nunca")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if EventLogger.shared.pendingCount > 0 {
                    Text("\(EventLogger.shared.pendingCount) pendientes")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

struct CardView<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        content()
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct StatItem: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.subheadline).fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DashboardPermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(description).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isGranted ? .green : .orange)
        }
    }
}

extension Date {
    var relativeString: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "hace \(Int(interval))s" }
        if interval < 3600 { return "hace \(Int(interval/60))min" }
        if interval < 86400 { return "hace \(Int(interval/3600))h" }
        return "hace \(Int(interval/86400))d"
    }
}
