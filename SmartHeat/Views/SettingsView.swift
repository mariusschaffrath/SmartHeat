import SwiftUI

struct StatusIndicator: View {
    let isActive: Bool
    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.gray.opacity(0.5))
            .frame(width: 10, height: 10)
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: StoveViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Ofen-Konfiguration")) {
                    Toggle("Wassergeführter Ofen", isOn: $viewModel.isWaterStove)
                        .tint(.blue)
                    Text("Aktivieren, um Kessel-Temperatur und Wasserdruck anzuzeigen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("🧪 Simulator / Gegenspieler (Testmodus)")) {
                    Toggle("Simulator-Modus verwenden", isOn: $viewModel.isSimulatorMode)
                        .tint(.purple)
                    Text("Verbindet mit dem lokalen Ofen- & Cloud-Simulator auf 127.0.0.1 zum Testen ohne echten Ofen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Cloud Anbindung")) {
                    if viewModel.authService.isAuthenticated {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Cloud: Online", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Spacer()
                                Button("Abmelden") {
                                    viewModel.logout()
                                    dismiss()
                                }
                                .foregroundColor(.red)
                            }
                            
                            if viewModel.authService.devices.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Keine Geräte automatisch gefunden.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Manuelle Device-ID (GUID):")
                                            .font(.caption2).bold()
                                        HStack {
                                            TextField("ID eingeben...", text: $viewModel.deviceId)
                                                .font(.system(size: 12, design: .monospaced))
                                                .textFieldStyle(.roundedBorder)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                            Button("Speichern") {
                                                dismiss()
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    Text("Diagnose (Server Antwort):")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                    
                                    Text(viewModel.cloudService.lastCloudResponse.isEmpty ? "Warten auf Antwort..." : viewModel.cloudService.lastCloudResponse)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .padding(8)
                                        .background(Color.black.opacity(0.05))
                                        .cornerRadius(8)
                                }
                            } else {
                                ForEach(viewModel.authService.devices) { device in
                                    Button(action: {
                                        viewModel.deviceId = device.id
                                        dismiss()
                                    }) {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(device.name).bold()
                                                Text("ID: \(device.id)").font(.system(size: 10, design: .monospaced))
                                            }
                                            Spacer()
                                            if viewModel.deviceId == device.id {
                                                Image(systemName: "checkmark").foregroundColor(.blue)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Nicht angemeldet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                // Hier nur zur Login-View navigieren, falls nötig
                                // Oder Dismiss, wenn der User sich neu einloggen will
                                dismiss()
                            }) {
                                Label("Zum Login", systemImage: "person.badge.plus")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                
                Section(header: Text("Lokale Verbindung (WLAN)")) {
                    HStack {
                        TextField("Manuelle IP", text: $viewModel.manualIP)
                            .keyboardType(.numbersAndPunctuation)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: viewModel.manualIP) { newValue in
                                let filtered = newValue.replacingOccurrences(of: ",", with: ".")
                                if filtered != newValue {
                                    viewModel.manualIP = filtered
                                }
                            }
                        Button("Verbinden") {
                            viewModel.socketService.connect(host: viewModel.manualIP)
                        }
                    }
                    
                    HStack {
                        Label("WLAN Status", systemImage: "wifi")
                        Spacer()
                        StatusIndicator(isActive: viewModel.socketService.isConnected)
                    }
                    
                    Button(action: {
                        viewModel.discoveryService.discoverStove()
                    }) {
                        HStack {
                            Label(viewModel.discoveryService.isScanning ? "Suche läuft..." : "Automatisch suchen", systemImage: "magnifyingglass")
                            if viewModel.discoveryService.isScanning {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.discoveryService.isScanning)
                }
                
                Section(header: Text("Discovery Logs")) {
                    Text(viewModel.discoveryService.logs.isEmpty ? "Bereit für Suche" : viewModel.discoveryService.logs)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
