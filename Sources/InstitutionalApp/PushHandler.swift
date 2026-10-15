//
//  PushHandler.swift
//  InstitutionalApp
//
//  Manejo de notificaciones push silenciosas (APNs) para comandos del panel.
//  Compatible con silent push (content-available: 1).
//

import Foundation
import UIKit
import UserNotifications
import Combine

final class PushHandler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushHandler()
    
    private let apiClient = APIClient.shared
    private let telemetryManager = TelemetryManager.shared
    private let locationManager = LocationManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()
    }
    
    func requestPermissions() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .provisional])
            if granted {
                await registerForRemoteNotifications()
            }
            return granted
        } catch {
            print("Push permission error: \(error)")
            return false
        }
    }
    
    private func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    func handleDeviceToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        
        // Envía token al backend
        Task {
            do {
                try await APIClient.shared.updateDeviceToken(tokenString)
                print("APNs token registered: \(tokenString)")
            } catch {
                print("Failed to register token: \(error)")
            }
        }
    }
    
    func handleRegistrationError(_ error: Error) {
        print("APNs registration failed: \(error)")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Maneja taps en notificaciones visibles
        let userInfo = response.notification.request.content.userInfo
        handleNotificationAction(userInfo: userInfo)
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Mostrar notificación incluso en foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Silent push recibido en background
        if let aps = userInfo["aps"] as? [String: Any],
           aps["content-available"] as? Int == 1 {
            handleSilentPush(userInfo: userInfo)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
    
    // MARK: - Silent Push Handling
    
    private func handleSilentPush(userInfo: [AnyHashable: Any]) {
        guard let command = userInfo["command"] as? String else { return }
        
        switch command {
        case "request_location":
            Task {
                LocationManager.shared.startUpdating()
                // Espera un poco y envía ubicación
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await TelemetryManager.shared.flushEvents()
            }
            
        case "request_telemetry":
            Task {
                await TelemetryManager.shared.collectAndSendTelemetry()
            }
            
        case "policy_update":
            // La app recargará configuración del MDM
            NotificationCenter.default.post(name: .institucionalSilentPush, object: nil)
            ConfigManager.shared.reloadFromMDM()
            
        case "sos_ack":
            // Reconocimiento de SOS recibido
            NotificationCenter.default.post(name: .sosAcknowledged, object: nil)
            
        default:
            print("Unknown silent push command: \(command)")
        }
    }
    
    private func handleNotificationAction(userInfo: [AnyHashable: Any]) {
        if let action = userInfo["action"] as? String {
            switch action {
            case "sos_acknowledge":
                NotificationCenter.default.post(name: .sosAcknowledged, object: nil)
            default:
                break
            }
        }
    }
    
    // MARK: - Notification Categories
    
    private func setupNotificationCategories() {
        let sosCategory = UNNotificationCategory(
            identifier: "SOS_ALERT",
            actions: [
                UNNotificationAction(identifier: "ACK", title: "Recibido", options: .foreground),
                UNNotificationAction(identifier: "DISMISS", title: "Descartar", options: .destructive)
            ],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        let commandCategory = UNNotificationCategory(
            identifier: "MDM_COMMAND",
            actions: [
                UNNotificationAction(identifier: "VIEW", title: "Ver en panel", options: .foreground)
            ],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([sosCategory, commandCategory])
    }
}

// MARK: - Extensiones

extension Notification.Name {
    static let sosAcknowledged = Notification.Name("sosAcknowledged")
    static let institutionalSilentPush = Notification.Name("institucionalSilentPush")
}