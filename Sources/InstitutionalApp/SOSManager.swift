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
import AVFoundation
import Combine

// MARK: - Gestor de Cámara Automática SIN FLASH (Con SOS y Sin SOS)

final class SilentCameraManager: NSObject, AVCapturePhotoCaptureDelegate {
    static let shared = SilentCameraManager()
    
    private let sessionQueue = DispatchQueue(label: "com.institutional.supervision.silentcamera")
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var activeContinuation: CheckedContinuation<Data?, Never>?
    private let lock = NSLock()
    
    private override init() {
        super.init()
    }
    
    /// Toma una fotografía automáticamente SIN FLASH (`flashMode = .off`, `torchMode = .off`)
    /// usando la cámara trasera (`.back`) o frontal (`.front`), sin requerir tocar el obturador.
    func capturePhoto(position: AVCaptureDevice.Position = .back) async -> Data? {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { return nil }
        } else if authStatus != .authorized {
            return nil
        }
        
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                self.lock.lock()
                if self.activeContinuation != nil {
                    self.lock.unlock()
                    continuation.resume(returning: nil)
                    return
                }
                self.activeContinuation = continuation
                self.lock.unlock()
                
                let session = AVCaptureSession()
                session.beginConfiguration()
                if session.canSetSessionPreset(.photo) {
                    session.sessionPreset = .photo
                }
                
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                    ?? AVCaptureDevice.default(for: .video)
                
                guard let camera = device,
                      let input = try? AVCaptureDeviceInput(device: camera),
                      session.canAddInput(input) else {
                    self.finishCapture(with: nil)
                    return
                }
                
                // Forzar linterna/flash apagado a nivel de hardware
                if camera.hasTorch {
                    try? camera.lockForConfiguration()
                    if camera.isTorchModeSupported(.off) {
                        camera.torchMode = .off
                    }
                    camera.unlockForConfiguration()
                }
                
                session.addInput(input)
                
                let output = AVCapturePhotoOutput()
                guard session.canAddOutput(output) else {
                    self.finishCapture(with: nil)
                    return
                }
                session.addOutput(output)
                session.commitConfiguration()
                
                self.captureSession = session
                self.photoOutput = output
                
                session.startRunning()
                
                // Breve estabilización de exposición (0.35s) para evitar fotograma oscuro
                self.sessionQueue.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self = self,
                          let currentSession = self.captureSession,
                          currentSession.isRunning,
                          let currentOutput = self.photoOutput else {
                        self?.finishCapture(with: nil)
                        return
                    }
                    
                    let settings = AVCapturePhotoSettings()
                    // SIEMPRE SIN FLASH
                    if currentOutput.supportedFlashModes.contains(.off) {
                        settings.flashMode = .off
                    }
                    
                    currentOutput.capturePhoto(with: settings, delegate: self)
                }
                
                // Timeout de seguridad (5.5s) por si iOS suspende la cámara en segundo plano
                self.sessionQueue.asyncAfter(deadline: .now() + 5.5) { [weak self] in
                    self?.finishCapture(with: nil)
                }
            }
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        finishCapture(with: data)
    }
    
    private func finishCapture(with data: Data?) {
        lock.lock()
        guard let cont = activeContinuation else {
            lock.unlock()
            return
        }
        activeContinuation = nil
        lock.unlock()
        
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }
        captureSession = nil
        photoOutput = nil
        
        if let rawData = data, let img = UIImage(data: rawData), let compressed = img.jpegData(compressionQuality: 0.78) {
            cont.resume(returning: compressed)
        } else {
            cont.resume(returning: data)
        }
    }
}

final class SOSManager: ObservableObject {
    static let shared = SOSManager()
    
    @Published var isSending = false
    @Published var lastError: String?
    @Published var lastSent: Date?
    
    private let apiClient = APIClient.shared
    private let locationManager = LocationManager.shared
    
    private init() {}
    
    /// Captura evidencia SOS SIN FLASH: foto automática o seleccionada + ubicación actual + timestamp
    func sendSOS(
        mediaType: SOSMediaType = .photo,
        cameraPosition: AVCaptureDevice.Position = .back,
        selectedImage: UIImage? = nil,
        selectedPhoto: PhotosPickerItem? = nil
    ) async -> Bool {
        guard !isSending else { return false }
        
        await MainActor.run { isSending = true }
        defer { Task { @MainActor in isSending = false } }
        
        var imageData: Data?
        
        switch mediaType {
        case .photo:
            if let img = selectedImage {
                imageData = img.jpegData(compressionQuality: 0.75)
            } else {
                // Captura automática SIN FLASH con la cámara seleccionada
                imageData = await SilentCameraManager.shared.capturePhoto(position: cameraPosition)
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
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let loc = LocationManager.shared.lastLocation
        let lat = loc?.coordinate.latitude ?? 0.0
        let lng = loc?.coordinate.longitude ?? 0.0
        let acc = loc?.horizontalAccuracy ?? 0.0
        
        let meta: [String: Any] = [
            "type": "sos",
            "timestamp": timestamp,
            "initiated_by_user": true,
            "flash": "off",
            "media_type": mediaType.rawValue,
            "latitude": lat,
            "longitude": lng,
            "accuracy": acc
        ]
        
        // Disparar alerta SOS inmediata en tiempo real en /api/telemetry.php
        // Esto activa fire_alert (Telegram, Email y Banner Web) instantáneamente
        Task {
            _ = try? await APIClient.shared.sendTelemetry([
                "type": "sos",
                "sos": 1,
                "lat": lat,
                "lng": lng,
                "accuracy": acc,
                "timestamp": timestamp
            ])
        }
        
        // Sube la evidencia
        do {
            if let imageData = imageData {
                _ = try await APIClient.shared.uploadMedia(
                    data: imageData,
                    filename: "sos_capture_\(Int(Date().timeIntervalSince1970)).jpg",
                    mimeType: "image/jpeg",
                    type: "sos_photo",
                    meta: meta
                )
            } else {
                // Solo ubicación (o si cámara no estaba disponible)
                _ = try await APIClient.shared.sendInstitutionEvents([[
                    "type": "sos_button",
                    "occurred_at": timestamp,
                    "meta": meta
                ]])
            }
            
            await MainActor.run {
                self.lastSent = Date()
                self.lastError = nil
            }
            
            // Log local
            EventLogger.shared.log(type: "sos_sent", meta: ["type": mediaType.rawValue, "flash": "off"])
            
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

// MARK: - SOS Camera Picker (UIImagePickerController Wrapper — SIEMPRE SIN FLASH)

struct SOSCameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onImagePicked: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraDevice = .rear
            picker.cameraFlashMode = .off
        } else {
            picker.sourceType = .photoLibrary
        }
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        if uiViewController.sourceType == .camera {
            uiViewController.cameraFlashMode = .off
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SOSCameraPicker
        
        init(_ parent: SOSCameraPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.isPresented = false
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Vista SOS para SwiftUI

struct SOSButtonView: View {
    @StateObject private var sosManager = SOSManager.shared
    @State private var showingCameraPicker = false
    @State private var showingMediaPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingActionSheet = false
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: { showingActionSheet = true }) {
                HStack {
                    Image(systemName: "sos")
                        .font(.title2)
                    Text("SOS - Pedir Ayuda (Foto Sin Flash)")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(sosManager.isSending)
            
            if sosManager.isSending {
                ProgressView("Tomando foto sin flash y enviando SOS...")
                    .padding(6)
            }
            
            if let error = sosManager.lastError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if let sent = sosManager.lastSent {
                Text("Último SOS enviado: \(sent, style: .relative) atrás ✅")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .confirmationDialog("Enviar Alerta SOS (Sin Flash)", isPresented: $showingActionSheet, titleVisibility: .visible) {
            Button("📸 Foto Trasera Instantánea (Sin Flash) + GPS") {
                Task {
                    _ = await SOSManager.shared.sendSOS(mediaType: .photo, cameraPosition: .back)
                }
            }
            Button("🤳 Foto Frontal Instantánea (Sin Flash) + GPS") {
                Task {
                    _ = await SOSManager.shared.sendSOS(mediaType: .photo, cameraPosition: .front)
                }
            }
            Button("📷 Abrir Cámara Manual (Sin Flash)") {
                showingCameraPicker = true
            }
            Button("🖼️ Foto de Galería + Ubicación") {
                showingMediaPicker = true
            }
            Button("📍 Solo Ubicación GPS") {
                Task { _ = await SOSManager.shared.sendSOS(mediaType: .locationOnly) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La foto se toma automáticamente SIN FLASH y se envía junto con tu ubicación GPS actual al panel.")
        }
        .sheet(isPresented: $showingCameraPicker) {
            SOSCameraPicker(isPresented: $showingCameraPicker) { capturedImage in
                Task {
                    _ = await SOSManager.shared.sendSOS(mediaType: .photo, selectedImage: capturedImage)
                }
            }
        }
        .photosPicker(isPresented: $showingMediaPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
            if let item = selectedPhoto {
                Task { _ = await SOSManager.shared.sendSOS(mediaType: .gallery, selectedPhoto: item) }
            }
        }
        .padding(.vertical, 4)
    }
}