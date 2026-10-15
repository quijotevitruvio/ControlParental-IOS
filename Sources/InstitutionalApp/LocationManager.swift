//
//  LocationManager.swift
//  InstitutionalApp
//
//  Gestión de ubicación en background con permiso "Siempre".
//  Compatible iOS 17+, Swift 5.9
//

import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isUpdating = false
    
    private var geofenceRegions: [CLCircularRegion] = []
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // metros
        manager.activityType = .other
        
        authorizationStatus = manager.authorizationStatus
    }
    
    func requestAlwaysPermission() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestAlwaysAuthorization()
    }
    
    func startUpdating() {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            return
        }
        if authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
        }
        isUpdating = true
        manager.startUpdatingLocation()
        
        // Rastreo de cambios significativos (despierta la app en background incluso tras reinicio)
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }
    
    func stopUpdating() {
        isUpdating = false
        manager.stopUpdatingLocation()
    }
    
    // MARK: - Geocercas
    
    func addGeofence(center: CLLocationCoordinate2D, radius: CLLocationDistance, identifier: String) {
        let region = CLCircularRegion(center: center, radius: radius, identifier: identifier)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        
        manager.startMonitoring(for: region)
        geofenceRegions.append(region)
        
        // Notifica al backend
        Task {
            await TelemetryManager.shared.logEvent(
                type: "geofence_configured",
                meta: ["geofence": region.identifier, "latitude": center.latitude, "longitude": center.longitude, "radius": region.radius]
            )
        }
    }
    
    func removeGeofence(identifier: String) {
        if let region = geofenceRegions.first(where: { $0.identifier == identifier }) {
            manager.stopMonitoring(for: region)
            geofenceRegions.removeAll { $0.identifier == identifier }
        }
    }
    
    func removeAllGeofences() {
        for region in geofenceRegions {
            manager.stopMonitoring(for: region)
        }
        geofenceRegions.removeAll()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        objectWillChange.send()
        
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            startUpdating()
        }
        
        // Notifica cambio de permiso si fue revocado
        if authorizationStatus != .authorizedAlways && authorizationStatus != .authorizedWhenInUse && authorizationStatus != .notDetermined {
            Task {
                await TelemetryManager.shared.logEvent(
                    type: "location_permission_revoked",
                    meta: ["status": String(describing: authorizationStatus)]
                )
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        
        Task {
            await TelemetryManager.shared.logEvent(
                type: "location_update",
                meta: [
                    "latitude": location.coordinate.latitude,
                    "longitude": location.coordinate.longitude,
                    "lat": location.coordinate.latitude,
                    "lng": location.coordinate.longitude,
                    "accuracy": location.horizontalAccuracy,
                    "speed_kmh": location.speed >= 0 ? location.speed * 3.6 : 0
                ]
            )
            TelemetryManager.shared.flushEvents()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circular = region as? CLCircularRegion else { return }
        
        Task {
            await TelemetryManager.shared.logEvent(
                type: "geofence_enter",
                meta: [
                    "geofence": region.identifier,
                    "latitude": circular.center.latitude,
                    "longitude": circular.center.longitude,
                    "radius": circular.radius
                ]
            )
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circular = region as? CLCircularRegion else { return }
        
        Task {
            await TelemetryManager.shared.logEvent(
                type: "geofence_exit",
                meta: [
                    "geofence": region.identifier,
                    "latitude": circular.center.latitude,
                    "longitude": circular.center.longitude,
                    "radius": circular.radius
                ]
            )
        }
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("Geofence monitoring failed: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        print("Started monitoring: \(region.identifier)")
    }
    
    func requestAlwaysAuthorization() {
        requestAlwaysPermission()
    }
    
    func saveState() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "location_last_state")
    }
}