//
//  UpdateManager.swift
//  InstitutionalApp
//
//  Gestor de actualizaciones automáticas desde GitHub Releases.
//  Detecta nuevas versiones y permite actualizar inalámbricamente con SideStore / AltStore o descarga directa.
//

import Foundation
import UIKit
import Combine

final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    private let repoApiURL = "https://api.github.com/repos/quijotevitruvio/ControlParental-IOS/releases/latest"
    private let directIpaURL = "https://github.com/quijotevitruvio/ControlParental-IOS/releases/latest/download/InstitutionalApp.ipa"
    
    @Published var isUpdateAvailable: Bool = false
    @Published var latestVersionName: String = ""
    @Published var latestBuildNumber: Int = 0
    @Published var releaseNotes: String = ""
    @Published var isChecking: Bool = false
    @Published var lastCheckDate: Date? = nil
    
    var currentBuildNumber: Int {
        if let str = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, let num = Int(str) {
            return num
        }
        return 28 // Build de referencia
    }
    
    var currentVersionName: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private init() {
        checkForUpdates()
    }
    
    func checkForUpdates() {
        guard let url = URL(string: repoApiURL) else { return }
        
        isChecking = true
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Empresas-App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                self?.lastCheckDate = Date()
                guard let data = data, error == nil else { return }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let tagName = json["tag_name"] as? String {
                        
                        let remoteBuild = self?.extractBuildNumber(from: tagName) ?? 0
                        let body = json["body"] as? String ?? "Nuevas mejoras de rendimiento, seguridad y estabilidad."
                        
                        self?.latestVersionName = tagName
                        self?.latestBuildNumber = remoteBuild
                        self?.releaseNotes = body
                        
                        if let current = self?.currentBuildNumber, remoteBuild > current {
                            self?.isUpdateAvailable = true
                        } else {
                            self?.isUpdateAvailable = false
                        }
                    }
                } catch {
                    print("Error parseando release: \(error)")
                }
            }
        }.resume()
    }
    
    private func extractBuildNumber(from tag: String) -> Int {
        let parts = tag.components(separatedBy: "-")
        if parts.count >= 2, let num = Int(parts.last!) {
            return num
        }
        return 0
    }
    
    func triggerUpdate() {
        let sidestoreURL = URL(string: "sidestore://install?url=\(directIpaURL)")!
        let altstoreURL = URL(string: "altstore://install?url=\(directIpaURL)")!
        let webDownloadURL = URL(string: directIpaURL)!
        
        if UIApplication.shared.canOpenURL(sidestoreURL) {
            UIApplication.shared.open(sidestoreURL)
        } else if UIApplication.shared.canOpenURL(altstoreURL) {
            UIApplication.shared.open(altstoreURL)
        } else {
            UIApplication.shared.open(webDownloadURL)
        }
    }
}
