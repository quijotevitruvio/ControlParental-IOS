//
//  ContentView.swift
//  InstitutionalApp
//  Pantalla principal de la app institucional con diseño moderno iOS 18 (Glassmorphism).
//

import SwiftUI
import AVFoundation
import MapKit

struct ContentView: View {
    @StateObject private var telemetry = TelemetryManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var sosManager = SOSManager.shared
    @StateObject private var pushHandler = PushHandler.shared
    @StateObject private var parentalAuth = ParentalAuthManager.shared
    @StateObject private var callManager = CallBlockerManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showingPermissions = false
    @State private var showingSettings = false
    @State private var showingCallBlocker = false
    
    @AppStorage("has_completed_onboarding_v1") private var hasCompletedOnboarding: Bool = false
    
    // Batería en tiempo real
    @State private var batteryLevel: Float = 1.0
    @State private var isCharging: Bool = false
    
    var body: some View {
        ZStack {
            if !hasCompletedOnboarding {
                OnboardingWizardView(isCompleted: $hasCompletedOnboarding)
                    .transition(.opacity)
                    .zIndex(2)
            } else if !parentalAuth.isUnlocked {
                ParentalLockView()
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                // Fondo con degradado sutil
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemGroupedBackground), Color(.secondarySystemGroupedBackground)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                mainDashboard
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background && hasCompletedOnboarding {
                parentalAuth.lock()
            }
        }
        .onAppear {
            autoRequestPermissions()
            updateBatteryInfo()
            updateManager.checkForUpdates()
        }
    }
    
    private var mainDashboard: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    if updateManager.isUpdateAvailable {
                        updateBannerCard
                    }
                    headerSection
                    statusWidgetsRow
                    mapLocationCard
                    callBlockerCard
                    permissionsStatusCard
                    telemetryCard
                    SOSButtonView()
                    lastSyncCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Empresas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingPermissions = true }) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundColor(.blue)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { parentalAuth.lock() }) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.red)
                        }
                        
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPermissions) {
                PermissionsView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingCallBlocker) {
                CallBlockerView()
            }
            .onAppear {
                if !TelemetryManager.shared.isUpdating { TelemetryManager.shared.start() }
                if LocationManager.shared.authorizationStatus == .authorizedAlways || LocationManager.shared.authorizationStatus == .authorizedWhenInUse {
                    LocationManager.shared.startUpdating()
                }
            }
        }
    }
    
    private func updateBatteryInfo() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : 1.0
        isCharging = (UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full)
    }
    
    private func autoRequestPermissions() {
        guard hasCompletedOnboarding else { return }
        let hasRequested = UserDefaults.standard.bool(forKey: "has_auto_requested_permissions")
        if !hasRequested {
            UserDefaults.standard.set(true, forKey: "has_auto_requested_permissions")
            Task {
                LocationManager.shared.requestAlwaysPermission()
                _ = await PushHandler.shared.requestPermissions()
                AVCaptureDevice.requestAccess(for: .video) { _ in }
            }
        }
    }
    
    // MARK: - Banner de Actualización
    
    var updateBannerCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.green)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Actualización Disponible")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text("\(updateManager.latestVersionName) lista para instalar")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { updateManager.triggerUpdate() }) {
                Text("Actualizar")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.08))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.green.opacity(0.25), lineWidth: 1)
        )
    }
    
    // MARK: - Header
    
    var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 50, height: 50)
                Image(systemName: "shield.checkered")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Empresas")
                    .font(.headline)
                    .fontWeight(.bold)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(NetworkMonitor.shared.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(NetworkMonitor.shared.isConnected ? "Conectado al Servidor" : "Modo Offline")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(ConfigManager.shared.isManaged ? "MDM" : "DIRECTO")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
                
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "v1.0")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Widgets de Estado (Batería y Conectividad)
    
    var statusWidgetsRow: some View {
        HStack(spacing: 12) {
            // Widget Batería
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 5)
                        .frame(width: 44, height: 44)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(max(batteryLevel, 0.05)))
                        .stroke(batteryColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44, height: 44)
                    
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.yellow)
                    } else {
                        Text("\(Int(batteryLevel * 100))%")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batería")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(isCharging ? "Cargando" : "\(Int(batteryLevel * 100))% restante")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
            
            // Widget Red
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(NetworkMonitor.shared.isConnected ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: NetworkMonitor.shared.connectionType == .wifi ? "wifi" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 18))
                        .foregroundColor(NetworkMonitor.shared.isConnected ? .green : .red)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Red")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(NetworkMonitor.shared.connectionTypeDescription)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
        }
    }
    
    private var batteryColor: Color {
        if batteryLevel > 0.5 { return .green }
        if batteryLevel > 0.2 { return .orange }
        return .red
    }
    
    // MARK: - Mini Mapa de Ubicación en Tiempo Real
    
    var mapLocationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Ubicación GPS en Vivo", systemImage: "location.fill")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Circle()
                    .fill(locationManager.authorizationStatus == .authorizedAlways ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                Text(locationManager.authorizationStatus == .authorizedAlways ? "Siempre Activo" : "En Uso")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if let loc = locationManager.lastLocation {
                // Mini Mapa
                Map(coordinateRegion: .constant(MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )), annotationItems: [loc]) { item in
                    MapMarker(coordinate: item.coordinate, tint: .blue)
                }
                .frame(height: 120)
                .cornerRadius(12)
                .disabled(true)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lat: \(loc.coordinate.latitude, specifier: "%.5f")  Lng: \(loc.coordinate.longitude, specifier: "%.5f")")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Margen de precisión: ±\(Int(loc.horizontalAccuracy)) metros")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        LocationManager.shared.startUpdating()
                        Task { await TelemetryManager.shared.collectAndSendTelemetry() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            } else {
                HStack {
                    Image(systemName: "location.slash")
                        .foregroundColor(.orange)
                    Text("Obteniendo satélites GPS...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Tarjeta de Bloqueo de Llamadas
    
    var callBlockerCard: some View {
        Button(action: { showingCallBlocker = true }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "phone.down.waves.left.and.right")
                        .font(.system(size: 18))
                        .foregroundColor(.purple)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bloqueador de Llamadas")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(callManager.blockedNumbers.count) número(s) en lista negra")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Permisos
    
    var permissionsStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Protecciones del Sistema")
                .font(.headline)
            
            DashboardPermissionRow(
                icon: "location.fill",
                title: "Ubicación",
                description: locationManager.authorizationStatus == .authorizedAlways ? "Permiso \"Siempre\" activo ✅" : "Toca para poner \"Siempre\" en Ajustes",
                isGranted: locationManager.authorizationStatus == .authorizedAlways,
                action: {
                    if locationManager.authorizationStatus == .notDetermined {
                        locationManager.requestAlwaysPermission()
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            )
            
            DashboardPermissionRow(
                icon: "bell.fill",
                title: "Notificaciones",
                description: "Alertas y sincronización silenciosa",
                isGranted: true,
                action: { Task { _ = await PushHandler.shared.requestPermissions() } }
            )
            
            DashboardPermissionRow(
                icon: "camera.fill",
                title: "Cámara SOS",
                description: "Para evidencia fotográfica de pánico",
                isGranted: true,
                action: {}
            )
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Telemetría
    
    var telemetryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transmisión al Panel")
                    .font(.headline)
                Spacer()
                if telemetry.isSending {
                    ProgressView().scaleEffect(0.7)
                }
            }
            
            HStack(spacing: 20) {
                StatItem(label: "Último Envío", value: telemetry.lastSent?.relativeString ?? "Al iniciar")
                StatItem(label: "En Cola", value: "\(EventLogger.shared.pendingCount)")
            }
            
            Button(action: { Task { await telemetry.flushEvents() } }) {
                HStack {
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sincronizar Ahora")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .font(.subheadline)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
    
    var lastSyncCard: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.secondary)
            Text("Sincronización automática activa cada 15 min")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// Extensión para que CLLocation sea Identifiable en MapKit
extension CLLocation: Identifiable {
    public var id: String {
        "\(coordinate.latitude),\(coordinate.longitude)"
    }
}

struct StatItem: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.subheadline).fontWeight(.bold)
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
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isGranted ? .blue : .orange)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                    Text(description).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(isGranted ? .green : .orange)
            }
        }
        .buttonStyle(.plain)
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
