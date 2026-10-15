import Foundation
import UIKit
import UserNotifications
import BackgroundTasks
import OSLog

/// AppDelegate handles application lifecycle, remote notifications, and background tasks
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    private let logger = Logger(subsystem: "com.institutional.supervision", category: "AppDelegate")
    private let apiClient = APIClient.shared
    private let pushHandler = PushHandler.shared
    private let telemetryManager = TelemetryManager.shared
    private let locationManager = LocationManager.shared
    private let configManager = ConfigManager.shared
    
    // MARK: - UIApplicationDelegate
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        logger.info("Application did finish launching")
        
        // Configure notification center
        UNUserNotificationCenter.current().delegate = self
        
        // Register for remote notifications
        registerForRemoteNotifications()
        
        // Register background tasks
        registerBackgroundTasks()
        
        // Load configuration from ManagedAppConfiguration
        configManager.loadConfiguration()
        
        // Initialize telemetry manager
        telemetryManager.start()
        
        // Initialize location manager
        locationManager.requestAlwaysAuthorization()
        
        // Handle launch from remote notification
        if let launchOptions = launchOptions,
           let remoteNotification = launchOptions[.remoteNotification] as? [AnyHashable: Any] {
            handleRemoteNotification(remoteNotification)
        }
        
        return true
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        logger.info("Registered for remote notifications with token: \(tokenString)")
        
        // Send device token to backend
        Task {
            do {
                try await apiClient.registerDeviceToken(tokenString)
            } catch {
                logger.error("Failed to register device token: \(error.localizedDescription)")
            }
        }
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        logger.info("Received remote notification: \(userInfo)")
        
        handleRemoteNotification(userInfo)
        
        // Process silent push in background
        pushHandler.processSilentPush(userInfo) { result in
            switch result {
            case .success:
                completionHandler(.newData)
            case .failure(let error):
                self.logger.error("Silent push processing failed: \(error.localizedDescription)")
                completionHandler(.failed)
            }
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        logger.info("Application did enter background")
        
        // Schedule background refresh task
        telemetryManager.scheduleBackgroundRefresh()
        
        // Notify config manager to check for updates
        NotificationCenter.default.post(name: .configShouldRefresh, object: nil)
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        logger.info("Application will enter foreground")
        
        // Refresh configuration
        configManager.loadConfiguration()
        
        // Flush any pending events
        Task {
            await EventLogger.shared.flush()
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        logger.info("Application will terminate")
        
        // Save any critical state
        telemetryManager.saveState()
        locationManager.saveState()
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        logger.info("User interacted with notification: \(userInfo)")
        
        // Handle notification actions
        handleNotificationAction(response.actionIdentifier, userInfo: userInfo)
        
        completionHandler()
    }
    
    // MARK: - Private Methods
    
    private func registerForRemoteNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge, .provisional]) { granted, error in
            if let error = error {
                self.logger.error("Notification authorization error: \(error.localizedDescription)")
            }
            
            if granted {
                self.logger.info("Notification authorization granted")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                self.logger.warning("Notification authorization denied")
            }
        }
    }
    
    private func registerBackgroundTasks() {
        guard let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] else {
            logger.warning("No BGTaskSchedulerPermittedIdentifiers configured")
            return
        }
        
        let refreshId = "com.institutional.supervision.telemetry-refresh"
        let processingId = "com.institutional.supervision.telemetry-processing"
        
        if permitted.contains(refreshId) {
            _ = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: refreshId,
                using: nil
            ) { task in
                self.handleTelemetryRefresh(task: task as! BGAppRefreshTask)
            }
        }
        
        if permitted.contains(processingId) {
            _ = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: processingId,
                using: nil
            ) { task in
                self.handleTelemetryProcessing(task: task as! BGProcessingTask)
            }
        }
        
        logger.info("Background tasks safely checked")
    }
    
    private func handleTelemetryRefresh(task: BGAppRefreshTask) {
        logger.debug("Handling telemetry refresh task")
        
        task.expirationHandler = {
            self.logger.warning("Telemetry refresh task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            await self.telemetryManager.collectAndSendTelemetry()
            self.telemetryManager.scheduleBackgroundRefresh()
            task.setTaskCompleted(success: true)
        }
    }
    
    private func handleTelemetryProcessing(task: BGProcessingTask) {
        logger.debug("Handling telemetry processing task")
        
        task.expirationHandler = {
            self.logger.warning("Telemetry processing task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            await self.telemetryManager.performDailyProcessing()
            self.telemetryManager.scheduleDailyProcessing()
            task.setTaskCompleted(success: true)
        }
    }
    
    private func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        // Check if it's a silent push (no aps alert)
        let aps = userInfo["aps"] as? [String: Any] ?? [:]
        let contentAvailable = aps["content-available"] as? Int ?? 0
        
        if contentAvailable == 1 {
            logger.debug("Received silent push notification")
            pushHandler.processSilentPush(userInfo) { _ in }
        } else {
            logger.debug("Received user-visible notification")
        }
    }
    
    private func handleNotificationAction(_ actionIdentifier: String, userInfo: [AnyHashable: Any]) {
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            logger.info("User tapped notification")
        case UNNotificationDismissActionIdentifier:
            logger.info("User dismissed notification")
        default:
            logger.info("User performed custom action: \(actionIdentifier)")
            // Handle custom actions if needed
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let configShouldRefresh = Notification.Name("com.institutional.supervision.configShouldRefresh")
    static let deviceTokenReceived = Notification.Name("com.institutional.supervision.deviceTokenReceived")
    static let locationPermissionChanged = Notification.Name("com.institutional.supervision.locationPermissionChanged")
}