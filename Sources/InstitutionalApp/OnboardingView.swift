//
//  OnboardingView.swift
//  InstitutionalApp
//
//  Pantalla de enrolamiento e inducción con escaneo de código QR
//  y vinculación directa con el panel web.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isCompleted: Bool
    
    @State var tokenInput: String = ""
    @State var isEnrolling: Bool = false
    @State var enrollError: String? = nil
    @State var enrollSuccess: Bool = false
    @State var showingQRScanner: Bool = false
    
    @ObservedObject private var configManager = ConfigManager.shared
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                        .padding(.top, 20)
                    
                    stepTokenInput
                    
                    if let err = enrollError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    if enrollSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("¡Dispositivo vinculado exitosamente!")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(12)
                    }
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $showingQRScanner) {
            QRScannerView(onCodeScanned: { scannedCode in
                handleScannedCode(scannedCode)
            }, onManualEntry: {
                showingQRScanner = false
            })
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 42))
                    .foregroundColor(.blue)
            }
            
            Text("Vinculación de Dispositivo")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Conecta este dispositivo con la consola institucional escaneando el código QR del panel o ingresando el token.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Paso de Entrada de Token / Escaneo de QR
    
    var stepTokenInput: some View {
        VStack(spacing: 18) {
            // Botón Prominente para Escaneo de QR del Panel
            Button(action: {
                showingQRScanner = true
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title2)
                    Text("📷 Escanear Código QR del Panel")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: .blue.opacity(0.25), radius: 6, x: 0, y: 3)
            }
            
            HStack {
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                Text("O INGRESA MANUALMENTE").font(.caption2).foregroundColor(.secondary)
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Token de Vinculación")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                TextField("Token alfanumérico o 'auto'", text: $tokenInput)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
            }
            
            Button(action: {
                performEnrollment(token: tokenInput)
            }) {
                HStack {
                    if isEnrolling {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "link.badge.plus")
                        Text("Vincular Dispositivo")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEnrolling ? Color.secondary.opacity(0.3) : Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEnrolling)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
    
    func handleScannedCode(_ rawCode: String) {
        guard let parsed = QRScannerView.parseEnrollmentCode(rawCode) else {
            enrollError = "Código QR no válido o no reconocido."
            return
        }
        
        if let server = parsed.server, !server.isEmpty {
            configManager.serverBase = server
            UserDefaults.standard.set(server, forKey: "server_base")
        }
        
        self.tokenInput = parsed.token
        performEnrollment(token: parsed.token)
    }
    
    func performEnrollment(token: String) {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }
        
        isEnrolling = true
        enrollError = nil
        
        Task {
            do {
                _ = try await APIClient.shared.enrollDevice(token: cleanToken)
                await MainActor.run {
                    self.isEnrolling = false
                    self.enrollSuccess = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.isCompleted = true
                    }
                }
            } catch {
                await MainActor.run {
                    self.isEnrolling = false
                    self.enrollError = "Error al vincular: \(error.localizedDescription)"
                }
            }
        }
    }
}
