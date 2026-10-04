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
    @ObservedObject var errorLogManager = StoveErrorLogManager.shared
    @ObservedObject var notificationManager = NotificationManager.shared
    @Environment(\.dismiss) var dismiss
    @AppStorage("app_appearance_mode") private var appearanceMode: String = "dark"
    
    @State private var showingTestNotificationSent = false
    @State private var showingPermissionDeniedAlert = false
    @State private var isSendingTestNotification = false
    
    private var appearanceDescription: String {
        switch appearanceMode {
        case "dark":
            return "Dunkelmodus ist dauerhaft aktiv (optimal für das Liquid Glass Design und OLED)."
        case "light":
            return "Helles Erscheinungsbild ist dauerhaft aktiv."
        default:
            return "Automatisch: Das Design passt sich dynamisch an die iOS-Systemeinstellungen an."
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Erscheinungsbild")) {
                    Toggle("Dunkelmodus immer ein", isOn: Binding(
                        get: { appearanceMode == "dark" },
                        set: { appearanceMode = $0 ? "dark" : "system" }
                    ))
                    .tint(.orange)
                    
                    Picker("Design-Modus", selection: $appearanceMode) {
                        Text("Automatisch").tag("system")
                        Text("Immer Dunkel").tag("dark")
                        Text("Immer Hell").tag("light")
                    }
                    .pickerStyle(.segmented)
                    
                    Text(appearanceDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Diagnose & Fehlerspeicher")) {
                    NavigationLink(destination: ErrorHistoryView(viewModel: viewModel)) {
                        HStack(spacing: 12) {
                            Image(systemName: errorLogManager.unresolvedCount > 0 ? "exclamationmark.triangle.fill" : "list.clipboard.fill")
                                .foregroundColor(errorLogManager.unresolvedCount > 0 ? .red : .orange)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fehler- & Alarmhistorie")
                                    .font(.subheadline.bold())
                                Text(errorLogManager.unresolvedCount > 0 ? "\(errorLogManager.unresolvedCount) aktive Störung(en)" : "Hardware-Fehlercodes mit Diagnose")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if errorLogManager.unresolvedCount > 0 {
                                Text("\(errorLogManager.unresolvedCount)")
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.red, in: Capsule())
                            }
                        }
                    }
                    
                    NavigationLink(destination: StoveDiagnosticsView(viewModel: viewModel)) {
                        HStack(spacing: 12) {
                            Image(systemName: "stethoscope")
                                .foregroundColor(.blue)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Betriebsdaten & Wartung")
                                    .font(.subheadline.bold())
                                Text("Laufzeit, Zündungen & 2.000h Service")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section(header: Text("Mitteilungen & Alarme")) {
                    Toggle("Pellet-Vorrat Warnung (< 4 kg)", isOn: $notificationManager.lowPelletNotifications)
                        .tint(.orange)
                    
                    Toggle("Ofen-Störungen & Alarme (Er01..15)", isOn: $notificationManager.stoveErrorNotifications)
                        .tint(.red)
                    
                    Toggle("Zündungsabschluss mitteilen", isOn: $notificationManager.ignitionFinishedNotifications)
                        .tint(.green)
                    
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task {
                            isSendingTestNotification = true
                            defer { isSendingTestNotification = false }
                            
                            let center = UNUserNotificationCenter.current()
                            let settings = await center.notificationSettings()
                            
                            if settings.authorizationStatus == .denied {
                                showingPermissionDeniedAlert = true
                                return
                            }
                            
                            let granted = await notificationManager.requestAuthorization()
                            if granted {
                                notificationManager.sendTestNotification { success in
                                    if success {
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            showingTestNotificationSent = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                showingTestNotificationSent = false
                                            }
                                        }
                                    }
                                }
                            } else {
                                showingPermissionDeniedAlert = true
                            }
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isSendingTestNotification {
                                ProgressView()
                                    .scaleEffect(0.85)
                            }
                            
                            Label(
                                showingTestNotificationSent ? "Test-Mitteilung gesendet! ✓" : "Test-Mitteilung senden",
                                systemImage: showingTestNotificationSent ? "checkmark.circle.fill" : "bell.badge.fill"
                            )
                            .font(.caption.bold())
                            .foregroundColor(showingTestNotificationSent ? .green : .orange)
                            
                            Spacer()
                        }
                    }
                    .disabled(isSendingTestNotification)
                }
                
                Section(header: Text("Verbindung & Cloud-Synchronisation")) {
                    HStack {
                        Label("Aktiver Pfad:", systemImage: "cloud.fill")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.authService.isAuthenticated ? Color.blue : Color.orange)
                                .frame(width: 8, height: 8)
                            Text("Dielle Cloud (Exklusiv)")
                                .font(.subheadline.bold())
                                .foregroundColor(.blue)
                        }
                    }
                    
                    HStack {
                        Text("Cloud-Status:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.authService.isAuthenticated ? "Verbunden & Aktiv" : "Nicht angemeldet")
                            .font(.caption.bold())
                            .foregroundColor(viewModel.authService.isAuthenticated ? .green : .orange)
                    }
                    
                    HStack {
                        Text("Polling-Intervall:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.0fs (%@)", viewModel.currentPollingInterval, viewModel.isStoveActive ? "Aktiv" : (viewModel.isUserInteracting ? "Bedienung" : "Eco-Standby")))
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle(isOn: $viewModel.isEcoModeEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Intelligentes Eco-Polling")
                                .font(.subheadline.bold())
                            Text(viewModel.isEcoModeEnabled ? "Spart bis zu 75% iPhone-Akku bei kaltem/ausgeschaltetem Ofen (30s Takt)." : "Permanenter 10s Takt.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(.green)
                    
                    if viewModel.isLowPowerMode {
                        HStack(spacing: 6) {
                            Image(systemName: "battery.50percent")
                                .foregroundColor(.yellow)
                            Text("iOS Stromsparmodus aktiv: Polling automatisch energieoptimiert.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("Exklusiver Cloud-Betrieb")
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                        }
                        
                        Text("Die lokale Port-80-Synchronisation wurde vollständig deaktiviert. Alle Statusabfragen und Steuerungsbefehle laufen dauerhaft, stabil und ortsunabhängig über die offizielle Dielle Azure Cloud – ohne Hin- und Herspringen im WLAN.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Ofen-Konfiguration")) {
                    Toggle("Wassergeführter Ofen", isOn: $viewModel.isWaterStove)
                        .tint(.blue)
                    Text("Aktivieren, um Kessel-Temperatur und Wasserdruck anzuzeigen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Zukünftige Features (Vorschau / Beta)")) {
                    Toggle("Pellet-Tank & Füllstandsanzeige", isOn: $viewModel.isPelletTankEnabled)
                        .tint(.orange)
                    Text("Berechnet und prognostiziert den Füllstand für den Dielle Ghibli Kombi 10 kW. Standardmäßig deaktiviert.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if viewModel.isPelletTankEnabled {
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
                }
                
                Section(header: Text("Home Assistant 24/7 Speicher & Sync")) {
                    Toggle("24/7 Historie & Pellettank aktivieren", isOn: $viewModel.haService.isEnabled)
                        .tint(.blue)
                    
                    Text("Wichtig: Die Steuerung des Ofens (Ein/Aus, Temperatur, Gebläse) erfolgt immer direkt über die Dielle Cloud. Home Assistant dient rein als 24/7-Datenspeicher für die Temperaturkurven und den kontinuierlichen Pelletstand.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if viewModel.haService.isEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server-Adresse (URL):").font(.caption).foregroundColor(.secondary)
                            TextField("http://192.168.178.131:8123", text: $viewModel.haService.serverURL)
                                .font(.system(size: 13, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        .padding(.vertical, 2)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Langlebiger Zugriffs-Token (Long-Lived Token):").font(.caption).foregroundColor(.secondary)
                            SecureField("Token aus Home Assistant Profil...", text: $viewModel.haService.accessToken)
                                .font(.system(size: 13, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 2)
                        
                        HStack {
                            Text("Status:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(viewModel.haService.statusMessage)
                                .font(.caption)
                                .foregroundColor(viewModel.haService.isConnected ? .green : .orange)
                        }
                        
                        if let lastSync = viewModel.haService.lastSyncDate {
                            HStack {
                                Text("Letzter Sync:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(lastSync.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Spacer()
                            Button(action: {
                                Task {
                                    _ = await viewModel.haService.testConnection()
                                    await viewModel.syncHomeAssistantData()
                                }
                            }) {
                                if viewModel.haService.isSyncing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Verbindung testen & synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
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
                
                Section(header: Text("4Heat Cloud Status")) {
                    HStack {
                        Label("Cloud Verbindung", systemImage: "cloud.fill")
                        Spacer()
                        StatusIndicator(isActive: viewModel.authService.isAuthenticated)
                    }
                    
                    HStack {
                        Text("Live Telemetrie")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.lastRawMessage.isEmpty ? "Verbunden" : viewModel.lastRawMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .alert("Mitteilungen deaktiviert", isPresented: $showingPermissionDeniedAlert) {
                Button("Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("SmartHeat darf dir aktuell keine Mitteilungen senden. Bitte aktiviere die Berechtigung in den iOS-Einstellungen unter Mitteilungen > SmartHeat.")
            }
        }
    }
}
