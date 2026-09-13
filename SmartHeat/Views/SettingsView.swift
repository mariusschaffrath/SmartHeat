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
                
                Section(header: Text("Pellet-Tank & Verbrauch (Ghibli Kombi 10 kW)")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Füllstand:")
                            Spacer()
                            Text("\(String(format: "%.1f", viewModel.pelletManager.currentLevel)) / \(String(format: "%.0f", viewModel.pelletManager.tankCapacity)) kg (\(String(format: "%.0f", viewModel.pelletManager.fillPercentage))%)")
                                .font(.system(.subheadline, design: .rounded).bold())
                                .foregroundColor(.orange)
                        }
                        
                        Slider(
                            value: $viewModel.pelletManager.currentLevel,
                            in: 0...viewModel.pelletManager.tankCapacity,
                            step: 0.5
                        )
                        .accentColor(.orange)
                    }
                    .padding(.vertical, 4)
                    
                    HStack {
                        Text("Tankkapazität")
                        Spacer()
                        Text("\(String(format: "%.0f", viewModel.pelletManager.tankCapacity)) kg")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Standard-Pelletsack")
                        Spacer()
                        Text("\(String(format: "%.0f", viewModel.pelletManager.bagWeight)) kg")
                            .foregroundColor(.secondary)
                    }
                    
                    if let lastRefill = viewModel.pelletManager.lastRefillDate {
                        HStack {
                            Text("Letzte Befüllung")
                            Spacer()
                            Text(lastRefill.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    DisclosureGroup("Verbrauchskalibrierung 10 kW") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Werkseitig hinterlegte Verbrauchsdaten:")
                                .font(.caption).bold()
                                .foregroundColor(.secondary)
                            
                            Group {
                                HStack { Text("• P1 (Teillast 2.8 kW):"); Spacer(); Text("0.65 kg/h (~31h)") }
                                HStack { Text("• P2 (Niedrig 4.5 kW):"); Spacer(); Text("0.95 kg/h (~21h)") }
                                HStack { Text("• P3 (Mittel 6.5 kW):"); Spacer(); Text("1.35 kg/h (~15h)") }
                                HStack { Text("• P4 (Hoch 8.5 kW):"); Spacer(); Text("1.80 kg/h (~11h)") }
                                HStack { Text("• P5 (Volllast 10 kW):"); Spacer(); Text("2.25 kg/h (~9h)") }
                                HStack { Text("• Scheitholzbetrieb:"); Spacer(); Text("0.00 kg/h (pausiert)") }
                                HStack { Text("• Zündungs-Primer:"); Spacer(); Text("200 g einmalig") }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
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
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Ofen-Zugangsdaten (myDielle / 4Heat):")
                                            .font(.caption2).bold()
                                        
                                        HStack {
                                            Text("Seriennummer / ID:").font(.caption)
                                            Spacer()
                                            TextField("ID eingeben...", text: $viewModel.deviceId)
                                                .font(.system(size: 12, design: .monospaced))
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 140)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                        }
                                        
                                        HStack {
                                            Text("PIN-Code:").font(.caption)
                                            Spacer()
                                            TextField("PIN eingeben...", text: $viewModel.stovePin)
                                                .font(.system(size: 12, design: .monospaced))
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 140)
                                                .keyboardType(.numberPad)
                                        }
                                        
                                        HStack {
                                            Spacer()
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
                
                Section(header: Text("Lokale Direktverbindung (WLAN)")) {
                    Toggle("WLAN-Direktverbindung verwenden", isOn: $viewModel.useWLANConnection)
                        .tint(.blue)
                    
                    if !viewModel.useWLANConnection {
                        Text("🔒 WLAN-Direktmodus ist deaktiviert. Die App kommuniziert ausschließlich über die Cloud (myDielle / 4Heat).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
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
