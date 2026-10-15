//
//  SOSManager.swift
//  InstitutionalApp
//
//  Botón SOS: evidencia voluntaria (foto + ubicación) enviada al panel.
//  El usuario elige qué compartir - SIEMPRE voluntario.
//


import Foundation
import SwiftUI
import PhotosUI
import CoreLocation
import Combine

final class SOSManager: ObservableObject {
    static let shared = SOSManager()
    
    @Published var isSending = false
    @Published var lastError: String?
    @Published var lastSent: Date?
    
    private let apiClient = APIClient.shared
    private let locationManager = LocationManager.shared
    
    private init() {}
    
    /// Captura evidencia SOS: foto + ubicación actual + timestamp
    /// El usuario elige: foto actual, galería, o solo ubicación
    func sendSOS(mediaType: SOSMediaType = .photo, selectedImage: UIImage? = nil, selectedPhoto: PhotosPickerItem? = nil) async -> Bool {
        guard !isSending else { return false }
        
        await MainActor.run { isSending = true }
        defer { Task { @MainActor in isSending = false } }
        
        var imageData: Data?
        
        switch mediaType {
        case .photo:
            if let img = selectedImage {
                imageData = img.jpegData(compressionQuality: 0.7)
            }
        case .gallery:
            if let item = selectedPhoto {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    imageData = data
                }
            }
        case .locationOnly:
            break
        }
        
        // Obtener ubicación actual
        let coordinate = LocationManager.shared.lastLocation?.coordinate
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        var meta: [String: Any] = [
            "type": "sos",
            "timestamp": timestamp,
            "initiated_by_user": true,
            "media_type": mediaType.rawValue
        ]
        
        if let coord = LocationManager.shared.lastLocation?.coordinate {
            meta["latitude"] = coordinate.latitude
            meta["longitude"] = coordinate.longitude
            meta["accuracy"] = LocationManager.shared.lastLocation?.horizontalAccuracy ?? 0
        }
        
        // Sube la evidencia
        do {
            if let imageData = imageData {
                _ = try await APIClient.shared.uploadMedia(data: imageData, type: "sos_photo", meta: meta)
            } else {
                // Solo ubicación
                _ = try await APIClient.shared.sendInstitutionEvents([[
                    "type": "sos_button",
                    "occurred_at": ISO8601DateFormatter().string(from: Date()),
                    "meta": meta
                ]])
            }
            
            await MainActor.run {
                self.lastSent = Date()
                self.lastError = nil
            }
            
            // Log local
            EventLogger.shared.log(context: "sos_sent", meta: ["type": mediaType.rawValue])
            
            return true
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
            return false
        }
    }
    
    enum SOSMediaType: String {
        case photo = "photo"
        case gallery = "gallery"
        case locationOnly = "location_only"
    }
}

// MARK: - Vista SOS para SwiftUI

struct SOSButtonView: View {
    @StateObject private var sosManager = SOSManager.shared
    @State private var showingMediaPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingActionSheet = false
    
    var body: some View {
        VStack(spacing: 16) {
            Button(action: { showingActionSheet = true }) {
                HStack {
                    Image(systemName: "sos")
                        .font(.title2)
                    Text("SOS - Pedir Ayuda")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(sosManager.isSending)
            
            if sosManager.isSending {
                ProgressView("Enviando SOS...")
                    .padding()
            }
            
            if let error = sosManager.lastError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if let sent = sosManager.lastSent {
                Text("Último envío: \(sent, style: .relative) atrás")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .confirmationDialog("Tipo de SOS", isPresented: $showingActionSheet, titleVisibility: .visible) {
            Button("Foto + Ubicación") {
                Task { await SOSManager.shared.sendSOS(mediaType: .photo) }
            }
            Button("Foto de Galería + Ubicación") {
                showingMediaPicker = true
            }
            Button("Solo Ubicación") {
                Task { await SOSManager.shared.sendSOS(mediaType: .locationOnly) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Elige qué evidencia enviar. La foto se toma al momento o se elige de galería. La ubicación actual se adjunta siempre.")
        }
        .photosPicker(isPresented: $showingMediaPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
            if let item = selectedPhoto {
                Task { await SOSManager.shared.sendSOS(mediaType: .gallery, selectedPhoto: item) }
            }
        }
        .padding()
    }
}