//
//  QRScannerView.swift
//  InstitutionalApp
//
//  Escáner interactivo de códigos QR para enrolamiento instantáneo
//  usando AVCaptureSession + AVCaptureMetadataOutput.
//

import SwiftUI
import AVFoundation

struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    
    var onCodeScanned: (String) -> Void
    var onManualEntry: (() -> Void)? = nil
    
    @State private var hasPermission: Bool = false
    @State private var isScanning: Bool = true
    @State private var scanLineOffset: CGFloat = -110
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if hasPermission {
                    QRScannerCameraRepresentable(isScanning: $isScanning) { scannedCode in
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        onCodeScanned(scannedCode)
                        dismiss()
                    }
                    .ignoresSafeArea()
                    
                    // Overlay de mira visual (Viewfinder)
                    viewfinderOverlay
                } else {
                    permissionDeniedView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            checkCameraPermission()
        }
    }
    
    // MARK: - Viewfinder y Animación
    
    private var viewfinderOverlay: some View {
        VStack(spacing: 24) {
            Text("Apunta al Código QR del Panel")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top, 40)
            
            Text("Escanea el QR de vinculación generado en el panel web para configurar este dispositivo.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            // Recuadro transparente con esquinas marcadas
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 250, height: 250)
                
                // Línea de escaneo láser animada
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .green, .clear]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 230, height: 3)
                    .offset(y: scanLineOffset)
                    .onAppear {
                        withAnimation(Animation.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                            scanLineOffset = 110
                        }
                    }
                
                // Esquinas resaltadas en verde
                VStack {
                    HStack {
                        CornerBracket(position: .topLeft)
                        Spacer()
                        CornerBracket(position: .topRight)
                    }
                    Spacer()
                    HStack {
                        CornerBracket(position: .bottomLeft)
                        Spacer()
                        CornerBracket(position: .bottomRight)
                    }
                }
                .frame(width: 250, height: 250)
            }
            
            Spacer()
            
            // Botón alternativo de ingreso manual
            if let manualAction = onManualEntry {
                Button(action: {
                    dismiss()
                    manualAction()
                }) {
                    HStack {
                        Image(systemName: "keyboard")
                        Text("Ingresar Token Manualmente")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.18))
                    .foregroundColor(.white)
                    .cornerRadius(24)
                }
                .padding(.bottom, 36)
            } else {
                Button(action: { dismiss() }) {
                    Text("Cerrar")
                        .font(.subheadline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.2))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                }
                .padding(.bottom, 36)
            }
        }
    }
    
    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 54))
                .foregroundColor(.orange)
            
            Text("Acceso a Cámara Requerido")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Se necesita permiso de cámara para leer el código QR de vinculación del panel.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            
            if let manualAction = onManualEntry {
                Button("Escribir Token a mano") {
                    dismiss()
                    manualAction()
                }
                .foregroundColor(.white)
                .font(.subheadline)
                .padding(.top, 8)
            }
        }
        .padding()
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.hasPermission = granted
                }
            }
        default:
            hasPermission = false
        }
    }
    
    // MARK: - Parser de Códigos de Enrolamiento
    
    /// Analiza códigos QR con soporte para:
    /// 1) JSON: {"server":"...","token":"..."}
    /// 2) URL con token=: https://.../panel/?token=abc123... (extrayendo también el servidor)
    /// 3) Token plano de 16+ o 32+ caracteres
    static func parseEnrollmentCode(_ raw: String) -> (server: String?, token: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // 1. Caso JSON: {"server": "...", "token": "..."}
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let token = (json["token"] as? String)
                ?? (json["enroll_token"] as? String)
                ?? (json["device_token"] as? String)
            let server = (json["server"] as? String)
                ?? (json["server_url"] as? String)
                ?? (json["server_base"] as? String)
            
            if let token = token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (server: server?.trimmingCharacters(in: .whitespacesAndNewlines),
                        token: token.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        
        // 2. Caso URL: https://.../panel/?token=abc123...
        if let url = URL(string: trimmed), let scheme = url.scheme, scheme.hasPrefix("http") {
            var extractedToken: String?
            
            // Buscar en query items
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
               let queryItems = components.queryItems {
                if let tItem = queryItems.first(where: { $0.name.lowercased() == "token" || $0.name.lowercased() == "enroll_token" }) {
                    extractedToken = tItem.value
                }
            }
            
            // Extraer origin (protocolo + host + puerto opcional)
            var origin: String? = nil
            if let host = url.host {
                let portStr = (url.port != nil && url.port != 80 && url.port != 443) ? ":\(url.port!)" : ""
                origin = "\(scheme)://\(host)\(portStr)"
            }
            
            if let tok = extractedToken, !tok.isEmpty {
                return (server: origin, token: tok)
            }
        }
        
        // 3. Caso Token alfanumérico plano (16+ o 32+ caracteres)
        let alphanumerics = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        if trimmed.count >= 16 && CharacterSet(charactersIn: trimmed).isSubset(of: alphanumerics) {
            return (server: nil, token: trimmed)
        }
        
        return nil
    }
}

// MARK: - Camera Representable

private struct QRScannerCameraRepresentable: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    var onCodeDetected: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        if isScanning {
            uiViewController.startScanning()
        } else {
            uiViewController.stopScanning()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, QRScannerViewControllerDelegate {
        let parent: QRScannerCameraRepresentable
        
        init(_ parent: QRScannerCameraRepresentable) {
            self.parent = parent
        }
        
        func qrScannerDidDetectCode(_ code: String) {
            parent.isScanning = false
            parent.onCodeDetected(code)
        }
    }
}

private protocol QRScannerViewControllerDelegate: AnyObject {
    func qrScannerDidDetectCode(_ code: String)
}

private class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: QRScannerViewControllerDelegate?
    
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCaptureSession()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    private func setupCaptureSession() {
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            return
        }
        
        captureSession.beginConfiguration()
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            if metadataOutput.availableMetadataObjectTypes.contains(.qr) {
                metadataOutput.metadataObjectTypes = [.qr]
            }
        }
        
        captureSession.commitConfiguration()
        
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.layer.bounds
        view.layer.addSublayer(layer)
        self.previewLayer = layer
        
        startScanning()
    }
    
    func startScanning() {
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }
    
    func stopScanning() {
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.stopRunning()
            }
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadata = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadata.type == .qr,
              let stringValue = metadata.stringValue else {
            return
        }
        
        stopScanning()
        delegate?.qrScannerDidDetectCode(stringValue)
    }
}

// MARK: - Esquinas para el visor

private struct CornerBracket: View {
    enum Position { case topLeft, topRight, bottomLeft, bottomRight }
    let position: Position
    
    var body: some View {
        Path { path in
            let length: CGFloat = 24
            switch position {
            case .topLeft:
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))
            case .topRight:
                path.move(to: CGPoint(x: -length, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: length))
            case .bottomLeft:
                path.move(to: CGPoint(x: 0, y: -length))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))
            case .bottomRight:
                path.move(to: CGPoint(x: -length, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: -length))
            }
        }
        .stroke(Color.green, lineWidth: 4)
        .frame(width: 24, height: 24)
    }
}
