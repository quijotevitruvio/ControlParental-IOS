import SwiftUI
import UIKit

@main
struct InstitutionalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    TelemetryManager.shared.start()
                }
        }
    }
}