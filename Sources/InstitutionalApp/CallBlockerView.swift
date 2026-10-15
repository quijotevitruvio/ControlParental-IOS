//
//  CallBlockerView.swift
//  InstitutionalApp
//
//  Vista para ver y gestionar la lista negra de llamadas y números bloqueados.
//

import SwiftUI

struct CallBlockerView: View {
    @ObservedObject private var callManager = CallBlockerManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var newNumber: String = ""
    @State private var newLabel: String = ""
    @State private var showingAddAlert = false
    
    var body: some View {
        NavigationView {
            List {
                // Estado de CallKit en iOS
                Section(header: Text("Estado del Filtro en iOS")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: callManager.isExtensionEnabled ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .foregroundColor(callManager.isExtensionEnabled ? .green : .orange)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(callManager.isExtensionEnabled ? "Filtro CallKit Activo" : "Requiere activación en Ajustes")
                                    .font(.headline)
                                Text(callManager.isExtensionEnabled ? "iOS bloquea automáticamente estas llamadas" : "Toca aquí para ver los pasos de activación")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if !callManager.isExtensionEnabled {
                            Button(action: {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                HStack {
                                    Text("Abrir Ajustes de iOS")
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Formulario para Agregar Número
                Section(header: Text("Bloquear Nuevo Número")) {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.secondary)
                            TextField("Ej: +573001234567 o 3001234567", text: $newNumber)
                                .keyboardType(.phonePad)
                        }
                        
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(.secondary)
                            TextField("Motivo / Nombre (ej: Desconocido, Spam)", text: $newLabel)
                        }
                        
                        Button(action: {
                            guard !newNumber.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let label = newLabel.trimmingCharacters(in: .whitespaces).isEmpty ? "Bloqueado por Supervisor" : newLabel
                            if callManager.addNumber(newNumber, label: label) {
                                newNumber = ""
                                newLabel = ""
                            }
                        }) {
                            HStack {
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                Text("Agregar a Lista Negra")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(newNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.vertical, 4)
                }
                
                // Lista de Números Bloqueados
                Section(header: Text("Números Bloqueados (\(callManager.blockedNumbers.count))")) {
                    if callManager.blockedNumbers.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                Image(systemName: "phone.badge.checkmark")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("No hay números bloqueados")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 16)
                            Spacer()
                        }
                    } else {
                        ForEach(callManager.blockedNumbers) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.number)
                                        .font(.headline)
                                    Text(item.label)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(action: {
                                    callManager.removeNumber(id: item.id)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                callManager.removeNumber(id: callManager.blockedNumbers[index].id)
                            }
                        }
                    }
                }
                
                // Guía de Activación en iOS
                Section(header: Text("Instrucciones de Bloqueo")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Ve a los **Ajustes** del iPhone.")
                        Text("2. Entra en **Teléfono** ➔ **Bloqueo e ID de llamadas**.")
                        Text("3. Activa el interruptor de **InstitutionalApp**.")
                        Text("4. Los números de esta lista serán rechazados automáticamente.")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Bloqueo de Llamadas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}
