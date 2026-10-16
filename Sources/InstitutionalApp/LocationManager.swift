//
//  LocationManager.swift
//  InstitutionalApp
//
//  Gestión de ubicación en background con permiso "Siempre".
//  Compatible iOS 17+, Swift 5.9
//

import Foundation
import UIKit
import CoreLocation
import Combine

// MARK: - Geofence Zone Model

struct GeofenceZone: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let lat: Double
    let lng: Double
    let radiusMeters: Double
    
    init(id: String, name: String, lat: Double, lng: Double, radiusMeters: Double) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lng = lng
        self.radiusMeters = radiusMeters
    }
    
    init?(dict: [String: Any]) {
        guard let rawId = dict["id"] else { return nil }
        self.id = "\(rawId)"
        self.name = (dict["name"] as? String) ?? "Zona \(self.id)"
        
        if let latVal = (dict["lat"] as? Double) ?? (dict["latitude"] as? Double) {
            self.lat = latVal
        } else if let latStr = dict["lat"] as? String, let latVal = Double(latStr) {
            self.lat = latVal
        } else {
            return nil
        }
        
        if let lngVal = (dict["lng"] as? Double) ?? (dict["longitude"] as? Double) {
            self.lng = lngVal
        } else if let lngStr = dict["lng"] as? String, let lngVal = Double(lngStr) {
            self.lng = lngVal
        } else {
            return nil
        }
        
        if let radVal = (dict["radius_m"] as? Double) ?? (dict["radius"] as? Double) ?? (dict["radius_meters"] as? Double) {
            self.radiusMeters = radVal
        } else if let radStr = dict["radius_m"] as? String, let radVal = Double(radStr) {
            self.radiusMeters = radVal
        } else {
            self.radiusMeters = 100.0
        }
    }
}

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
        manager.distanceFilter = 5 // metros
        manager.activityType = .other
        
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            startTracking()
        }
    }
    
    func requestAlwaysPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestAlwaysAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            openSettings()
        }
    }
    
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
    }
    
    func startTracking() {
        startUpdating()
        if CLLocationManager.isMonitoringAvailable(for: CLVisit.self) {
            manager.startMonitoringVisits()
        }
    }
    
    func stopTracking() {
        stopUpdating()
        if CLLocationManager.isMonitoringAvailable(for: CLVisit.self) {
            manager.stopMonitoringVisits()
        }
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
        manager.requestLocation()
        
        // Rastreo de cambios significativos (despierta la app en background incluso tras reinicio)
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }
    
    func stopUpdating() {
        isUpdating = false
        manager.stopUpdatingLocation()
    }
    
    func refreshLocation() {
        startUpdating()
        manager.requestLocation()
    }
    
    func requestImmediateLocation() {
        manager.desiredAccuracy = kCLLocationAccuracyBest
        refreshLocation()
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
        
        // Ajuste adaptativo de precisión según movimiento para ahorro de batería
        if location.speed > 2.0 {
            if manager.desiredAccuracy != kCLLocationAccuracyBest {
                manager.desiredAccuracy = kCLLocationAccuracyBest
            }
        } else if location.speed <= 0.5 && location.speed >= 0 {
            if manager.desiredAccuracy != kCLLocationAccuracyHundredMeters {
                manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            }
        }
        
        Task {
            await TelemetryManager.shared.logEvent(
                type: "location_update",
                meta: [
                    "latitude": location.coordinate.latitude,
                    "longitude": location.coordinate.longitude,
                    "lat": location.coordinate.latitude,
                    "lng": location.coordinate.longitude,
                    "accuracy": location.horizontalAccuracy,
                    "altitude": location.altitude,
                    "speed": location.speed >= 0 ? location.speed : 0,
                    "speed_kmh": location.speed >= 0 ? location.speed * 3.6 : 0
                ]
            )
            await TelemetryManager.shared.flushEvents()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task {
            await TelemetryManager.shared.logEvent(
                type: "location_visit",
                meta: [
                    "latitude": visit.coordinate.latitude,
                    "longitude": visit.coordinate.longitude,
                    "lat": visit.coordinate.latitude,
                    "lng": visit.coordinate.longitude,
                    "horizontal_accuracy": visit.horizontalAccuracy,
                    "accuracy": visit.horizontalAccuracy,
                    "arrival_date": ISO8601DateFormatter().string(from: visit.arrivalDate),
                    "departure_date": ISO8601DateFormatter().string(from: visit.departureDate)
                ]
            )
            await TelemetryManager.shared.flushEvents()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
    
    // MARK: - Sincronización de Geocercas con el Servidor
    
    func syncGeofences(_ serverZones: [GeofenceZone]) {
        let existingIds = Set(geofenceRegions.map { $0.identifier })
        let newIds = Set(serverZones.map { $0.id })
        
        if existingIds == newIds {
            return
        }
        
        // Detener monitoreo de zonas que ya no están en la política del servidor
        for region in geofenceRegions where !newIds.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        geofenceRegions.removeAll { !newIds.contains($0.identifier) }
        
        // Agregar y monitorear nuevas zonas del servidor
        for zone in serverZones where !existingIds.contains(zone.id) {
            let center = CLLocationCoordinate2D(latitude: zone.lat, longitude: zone.lng)
            let region = CLCircularRegion(center: center, radius: zone.radiusMeters, identifier: zone.id)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
            geofenceRegions.append(region)
        }
        print("Geocercas sincronizadas con servidor: \(geofenceRegions.count) activas")
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