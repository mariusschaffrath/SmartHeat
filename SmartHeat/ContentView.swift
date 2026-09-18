//
//  ContentView.swift
//  SmartHeat
//
//  Pure Cloud Dashboard fully upgraded to Apple Liquid Glass Design Guidelines (HIG).
//  Features multi-tier specular caustics, molten liquid dial, 2-second hold-to-unlock,
//  illuminated glass modulation vials, and ducted fan controls.
//

import SwiftUI

// MARK: - Apple Liquid Glass Design System
public struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 24
    var tintColor: Color = .clear
    var tintOpacity: Double = 0.08
    var specularOpacity: Double = 0.45
    
    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .background {
                if tintColor != .clear {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tintColor.opacity(tintOpacity))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(specularOpacity), location: 0.0),
                                .init(color: Color.white.opacity(specularOpacity * 0.35), location: 0.28),
                                .init(color: Color.white.opacity(0.05), location: 0.65),
                                .init(color: Color.white.opacity(specularOpacity * 0.30), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
    }
}

public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 24,
        tint: Color = .clear,
        tintOpacity: Double = 0.08,
        specularOpacity: Double = 0.45
    ) -> some View {
        self.modifier(LiquidGlassCardModifier(
            cornerRadius: cornerRadius,
            tintColor: tint,
            tintOpacity: tintOpacity,
            specularOpacity: specularOpacity
        ))
    }
}

// MARK: - Fluid Liquid Scale Button Style
struct LiquidScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Main ContentView
// MARK: - Main ContentView with 3-Tab Architecture
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = StoveViewModel()
    @AppStorage("has_saved_account") private var hasSavedAccount: Bool = false
    @AppStorage("app_appearance_mode") private var appearanceMode: String = "dark"
    @State private var selectedTab: Int = 0
    @State private var isSplashVisible: Bool = true
    
    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "dark": return .dark
        case "light": return .light
        default: return nil // Automatisch (System)
        }
    }
    
    private var hasAuthenticatedAccount: Bool {
        hasSavedAccount ||
        UserDefaults.standard.string(forKey: "cloud_token") != nil ||
        KeychainService.shared.load(key: "cloud_email") != nil
    }
    
    var body: some View {
        Group {
            if !hasAuthenticatedAccount {
                OnboardingView(viewModel: viewModel)
            } else {
                ZStack {
                    TabView(selection: $selectedTab) {
                        HomeDashboardView(viewModel: viewModel)
                            .tabItem {
                                Label("Home", systemImage: "flame.fill")
                            }
                            .tag(0)
                        
                        HeatingScheduleView(viewModel: viewModel)
                            .tabItem {
                                Label("Heizpläne", systemImage: "calendar.badge.clock")
                            }
                            .tag(1)
                        
                        SettingsView(viewModel: viewModel)
                            .tabItem {
                                Label("Einstellungen", systemImage: "gearshape.fill")
                            }
                            .tag(2)
                    }
                    .tint(.orange)
                    
                    // Liquid Glass Splash Overlay to eliminate cold-start / resume flashing
                    if isSplashVisible {
                        splashOverlay
                            .transition(.opacity)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            isSplashVisible = false
                        }
                    }
                }
                .alert(item: $viewModel.activeError) { error in
                    Alert(
                        title: Text("[\(error.code)] \(error.title)"),
                        message: Text("\(error.errorDescription ?? "")\n\n💡 Empfehlung:\n\(error.suggestion)"),
                        dismissButton: .default(Text("Verstanden"))
                    )
                }
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                viewModel.resumePolling()
            case .inactive, .background:
                viewModel.pausePolling()
            @unknown default:
                break
            }
        }
    }
    
    private var splashOverlay: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            
            RadialGradient(
                colors: [Color.orange.opacity(0.18), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 380
            )
            .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 90, height: 90)
                        .blur(radius: 8)
                    
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: .orange.opacity(0.4), radius: 10, y: 4)
                }
                
                Text("SmartHeat")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Wird geladen...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Home Dashboard View (without gear button)
struct HomeDashboardView: View {
    @ObservedObject var viewModel: StoveViewModel
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            
            // Liquid Ambient Lighting (Sub-surface dispersion)
            RadialGradient(
                gradient: Gradient(colors: [
                    viewModel.isHeating ? Color.orange.opacity(0.16) : Color.orange.opacity(0.08),
                    .clear
                ]),
                center: .topTrailing,
                startRadius: 10,
                endRadius: 550
            )
            .ignoresSafeArea()
            
            ZStack(alignment: .top) {
                // 1. Full-bleed Scrollable Dashboard (scrolls freely UNDER the floating header)
                DashboardView(viewModel: viewModel)
                    .ignoresSafeArea(edges: .top)
                
                // 2. Floating Liquid Glass Header Card (Pure Apple Liquid Glass)
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text("SmartHeat")
                                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                // Dezent: Cloud-Verbindungsstatus (stilles Icon)
                                if viewModel.authService.isAuthenticated {
                                    Image(systemName: "checkmark.icloud.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.green.opacity(0.85))
                                }
                            }
                            
                            // Die 4 klaren farblichen Statements: AUS, EIN, STANDBY, ZÜNDUNG
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(viewModel.operationalState.color)
                                    .frame(width: 8, height: 8)
                                    .shadow(color: viewModel.operationalState.color.opacity(0.6), radius: 3)
                                
                                Text(viewModel.operationalState.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(viewModel.operationalState.color)
                                
                                if viewModel.operationalState == .on && viewModel.powerLevel > 0 {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text("Stufe \(viewModel.powerLevel)")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Status Indicator Badge (Cloud / 24/7 HA)
                        HStack(spacing: 6) {
                            if viewModel.haService.isConnected && viewModel.haService.isEnabled {
                                HStack(spacing: 4) {
                                    Image(systemName: "server.rack")
                                        .font(.system(size: 10))
                                    Text("24/7 HA")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 10))
                                    Text("Cloud")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .liquidGlass(
                        cornerRadius: 24,
                        tint: viewModel.operationalState.color,
                        tintOpacity: 0.08,
                        specularOpacity: 0.75
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
        }
    }
}

// MARK: - Dashboard View
struct DashboardView: View {
    @ObservedObject var viewModel: StoveViewModel
    @State private var showingRoomTempDetail = false
    @State private var showingExhaustTempDetail = false
    @State private var showingUnlockConfirmation = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Initialer Abstand, damit die Inhalte im Ruhezustand sauber unter dem schwebenden Liquid Glass Header sitzen
                Color.clear
                    .frame(height: 136)
                
                // 0. Active Hardware Alarm Hero Banner (Quittieren & Entsperren)
                if viewModel.isStoveLockedByAlarm {
                    activeAlarmBanner
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                }
                
                // 0.5. Scheitholz-Betriebsführung Hero (Kombi 10 kW Spezial)
                if viewModel.isWoodMode {
                    woodCombustionHeroCard
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                }
                
                // 1. Temperatur-Kacheln (Raum & Abgas)
                HStack(spacing: 14) {
                    Button {
                        showingRoomTempDetail = true
                    } label: {
                        TempCard(
                            title: "Raum",
                            value: String(format: "%.1f", viewModel.currentTemp),
                            unit: "°C",
                            icon: "house.fill",
                            color: .orange,
                            showChevron: true
                        )
                    }
                    .buttonStyle(LiquidScaleButtonStyle())
                    
                    Button {
                        showingExhaustTempDetail = true
                    } label: {
                        TempCard(
                            title: "Abgas",
                            value: String(format: "%.0f", viewModel.exhaustTemp),
                            unit: "°C",
                            icon: "thermometer.high",
                            color: .red,
                            showChevron: true
                        )
                    }
                    .buttonStyle(LiquidScaleButtonStyle())
                }
                
                // Optionaler Wasserofen
                if viewModel.isWaterStove {
                    HStack(spacing: 14) {
                        TempCard(title: "Kessel", value: String(format: "%.1f", viewModel.waterTemp), unit: "°C", icon: "drop.fill", color: .blue)
                        TempCard(title: "Druck", value: String(format: "%.2f", viewModel.waterPressure), unit: "bar", icon: "gauge", color: .green)
                    }
                }
                
                // Optionaler Pellettank
                if viewModel.isPelletTankEnabled {
                    PelletTankCard(pelletManager: viewModel.pelletManager, stoveStatus: viewModel.stoveStatus)
                }
                
                // 2. Ziel-Temperatur (DIREKT UNTER RAUM UND ABGAS)
                VStack(spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ZIEL-TEMPERATUR")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .tracking(1.2)
                                .foregroundColor(.secondary)
                            
                            if viewModel.hasPendingTargetSync {
                                HStack(spacing: 4) {
                                    Text("Synchronisiere mit Ofen...")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(.orange)
                                }
                            } else if viewModel.isTargetLocked {
                                Text("Gesperrt")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary.opacity(0.8))
                            } else {
                                Text("Freigeschaltet (Autosperre nach 1 min)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Spacer()
                        
                        // Schloss Button (Icon-only: Schloss zu = gesperrt, Schloss offen = entsperrt)
                        LockToggleButton(isLocked: $viewModel.isTargetLocked)
                    }
                    
                    // Prägnanter, breiterer Thermostat-Kreis (30pt Molten Liquid Arc, 260pt)
                    ThermostatDial(value: $viewModel.targetTemp, range: 10...35) {
                        // onIDLE
                        if !viewModel.isTargetLocked {
                            viewModel.setTemperature(viewModel.targetTemp)
                        }
                    } onDrag: {
                        // onDrag
                        viewModel.triggerInteractionLock()
                    }
                    .frame(height: 260)
                    .opacity(viewModel.isTargetLocked ? 0.65 : 1.0)
                    .disabled(viewModel.isTargetLocked)
                    
                    // Liquid Stepper Tasten (- und +)
                    HStack(spacing: 30) {
                        Button(action: {
                            if viewModel.isTargetLocked {
                                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            } else {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                viewModel.decrementTargetTemp()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isTargetLocked ? Color.gray.opacity(0.1) : Color.orange.opacity(0.14))
                                    .frame(width: 54, height: 54)
                                    .overlay {
                                        if viewModel.isTargetLocked {
                                            Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                        } else {
                                            Circle().strokeBorder(
                                                LinearGradient(colors: [Color.orange.opacity(0.6), Color.white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                                lineWidth: 1
                                            )
                                        }
                                    }
                                    .shadow(color: viewModel.isTargetLocked ? Color.clear : Color.orange.opacity(0.25), radius: 6, y: 2)
                                
                                Image(systemName: "minus")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(viewModel.isTargetLocked ? .secondary : .orange)
                            }
                        }
                        .buttonStyle(LiquidScaleButtonStyle())
                        .disabled(viewModel.isTargetLocked)
                        
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f°C", viewModel.targetTemp))
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundColor(viewModel.isTargetLocked ? .secondary : .primary)
                            Text(viewModel.isTargetLocked ? "Gesperrt" : "±0.5°C Tasten")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .frame(minWidth: 95)
                        
                        Button(action: {
                            if viewModel.isTargetLocked {
                                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            } else {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                viewModel.incrementTargetTemp()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isTargetLocked ? Color.gray.opacity(0.1) : Color.orange.opacity(0.14))
                                    .frame(width: 54, height: 54)
                                    .overlay {
                                        if viewModel.isTargetLocked {
                                            Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                        } else {
                                            Circle().strokeBorder(
                                                LinearGradient(colors: [Color.orange.opacity(0.6), Color.white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                                lineWidth: 1
                                            )
                                        }
                                    }
                                    .shadow(color: viewModel.isTargetLocked ? Color.clear : Color.orange.opacity(0.25), radius: 6, y: 2)
                                
                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(viewModel.isTargetLocked ? .secondary : .orange)
                            }
                        }
                        .buttonStyle(LiquidScaleButtonStyle())
                        .disabled(viewModel.isTargetLocked)
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 20)
                .liquidGlass(cornerRadius: 30, tint: .orange, tintOpacity: viewModel.isHeating ? 0.05 : 0.02, specularOpacity: 0.55)
                
                // 3. Ofen-Leistungsstufe (Illuminated Liquid Glass Vials)
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(viewModel.operationalState.color.opacity(0.18))
                            .frame(width: 38, height: 38)
                            .overlay(Circle().strokeBorder(viewModel.operationalState.color.opacity(0.35), lineWidth: 1))
                        
                        Image(systemName: "flame.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(viewModel.operationalState.color)
                            .shadow(color: viewModel.operationalState == .on ? Color.orange.opacity(0.7) : .clear, radius: 4)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OFEN-LEISTUNGSSTUFE")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.1)
                            .foregroundColor(.secondary)
                        
                        Text(viewModel.operationalState == .on ? "Stufe \(viewModel.powerLevel)" : viewModel.operationalState.title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // 5 Beleuchtete Liquid Glass Vials (P1 - P5)
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { level in
                            let isActive = level <= viewModel.powerLevel && viewModel.isHeating
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(
                                    isActive ?
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.6, blue: 0.1), Color(red: 0.95, green: 0.25, blue: 0.1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ) :
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 8, height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(
                                            isActive ? Color.white.opacity(0.55) : Color.white.opacity(0.12),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(color: isActive ? Color.orange.opacity(0.45) : .clear, radius: 4, y: 1)
                        }
                    }
                }
                .padding(18)
                .liquidGlass(cornerRadius: 24, tint: .orange, tintOpacity: viewModel.isHeating ? 0.04 : 0.01)
                
                // 4. Luftheizung Flur (Kanal 1 - Azure Liquid Glass)
                let currentSpeed = viewModel.kanal1FanSpeed
                let speedText = currentSpeed == 0 ? "Aus" : (currentSpeed == 6 ? "Auto" : "P\(currentSpeed)")
                let isActiveHeating = currentSpeed > 0 && viewModel.isHeating
                
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(isActiveHeating ? Color.blue.opacity(0.18) : Color.gray.opacity(0.1))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle().strokeBorder(
                                            isActiveHeating ? Color.blue.opacity(0.35) : Color.white.opacity(0.15),
                                            lineWidth: 1
                                        )
                                    )
                                
                                Image(systemName: "wind")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(isActiveHeating ? .blue : .secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("LUFTHEIZUNG FLUR")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .tracking(1.1)
                                    .foregroundColor(.secondary)
                                
                                if currentSpeed == 0 {
                                    Text("Gebläse Aus")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.secondary)
                                } else if viewModel.isHeating {
                                    Text("Kanalgebläse aktiv • Stufe \(speedText)")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                } else {
                                    Text("Kanalgebläse Stufe \(speedText)")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Badge oben rechts (Apple Liquid Glass Pill)
                        let badgeLabel = currentSpeed == 0 ? "AUS" : speedText
                        Text(badgeLabel)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background(isActiveHeating ? Color.blue.opacity(0.16) : Color.white.opacity(0.06))
                            .foregroundColor(isActiveHeating ? .blue : .secondary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    isActiveHeating ? Color.blue.opacity(0.35) : Color.white.opacity(0.15),
                                    lineWidth: 1
                                )
                            )
                            .shadow(color: isActiveHeating ? Color.blue.opacity(0.25) : .clear, radius: 4, y: 1)
                    }
                    
                    // Liquid Segment Buttons: Aus, P1..P5, Auto (Werte: 0, 1..5, 6)
                    let speedOptions: [(label: String, val: Int)] = [
                        ("Aus", 0),
                        ("P1", 1),
                        ("P2", 2),
                        ("P3", 3),
                        ("P4", 4),
                        ("P5", 5),
                        ("Auto", 6)
                    ]
                    
                    HStack(spacing: 5) {
                        ForEach(speedOptions, id: \.val) { opt in
                            let isSelected = (currentSpeed == opt.val)
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.setKanalFanSpeed(channel: 1, speed: opt.val)
                            }) {
                                Text(opt.label)
                                    .font(.system(size: opt.val == 0 || opt.val == 6 ? 10 : 12, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background {
                                        if isSelected {
                                            LinearGradient(colors: [Color.blue, Color(red: 0.1, green: 0.5, blue: 0.95)], startPoint: .top, endPoint: .bottom)
                                        } else {
                                            Color.white.opacity(0.06)
                                        }
                                    }
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(
                                                isSelected ? Color.white.opacity(0.55) : Color.white.opacity(0.12),
                                                lineWidth: 1
                                            )
                                    }
                                    .shadow(color: isSelected ? Color.blue.opacity(0.35) : .clear, radius: 4, y: 1)
                            }
                            .buttonStyle(LiquidScaleButtonStyle())
                        }
                    }
                }
                .padding(18)
                .liquidGlass(cornerRadius: 24, tint: .blue, tintOpacity: isActiveHeating ? 0.04 : 0.01)
                
                // 5. Einschalten / Ausschalten (Liquid Glass Action Buttons)
                HStack(spacing: 14) {
                    ModernActionButton(title: "Einschalten", icon: "power", color: .green) {
                        viewModel.turnOn()
                    }
                    ModernActionButton(title: "Ausschalten", icon: "power", color: .red) {
                        viewModel.turnOff()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .onAppear {
            viewModel.refreshData()
        }
        .sheet(isPresented: $showingRoomTempDetail) {
            RoomTempDetailView(
                historyManager: viewModel.historyManager,
                currentTemp: viewModel.currentTemp,
                targetTemp: viewModel.targetTemp
            )
        }
        .sheet(isPresented: $showingExhaustTempDetail) {
            ExhaustTempDetailView(
                historyManager: viewModel.historyManager,
                currentExhaustTemp: viewModel.exhaustTemp,
                stoveStatus: viewModel.stoveStatus
            )
        }
    }
    
    @ViewBuilder
    private var activeAlarmBanner: some View {
        let alarm = viewModel.activeHardwareAlarm
        let codeText = alarm?.codeString ?? (viewModel.stoveErrorCode > 0 ? String(format: "Er%02d", viewModel.stoveErrorCode) : "ALARM")
        let titleText = alarm?.title ?? "Ofen verriegelt (Sicherheitsabschaltung)"
        let descText = alarm?.description ?? "Die Ofenplatine hat den Betrieb aus Sicherheitsgründen gestoppt."
        let remedyText = alarm?.remedy ?? "Brennkammer kontrollieren und Störung quittieren."
        
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.red)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(codeText)
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                        
                        Text(titleText)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                    
                    Text(descText)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // Remedy box
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                    Text("Empfohlene Behebung:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                }
                
                Text(remedyText)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            
            // Unlock action button
            Button {
                showingUnlockConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isUnlocking {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "lock.open.trianglebadge.exclamationmark.fill")
                            .font(.system(size: 15, weight: .bold))
                    }
                    
                    Text(viewModel.isUnlocking ? "Wird entsperrt..." : "Störung quittieren & Ofen entsperren")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .foregroundColor(.white)
                .shadow(color: Color.red.opacity(0.4), radius: 8, y: 3)
            }
            .disabled(viewModel.isUnlocking)
            .buttonStyle(LiquidScaleButtonStyle())
        }
        .padding(18)
        .liquidGlass(
            cornerRadius: 24,
            tint: .red,
            tintOpacity: 0.12,
            specularOpacity: 0.7
        )
        .confirmationDialog(
            "Ofen entsperren?",
            isPresented: $showingUnlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("Störung quittieren & Entsperren", role: .none) {
                Task {
                    await viewModel.unlockStoveAlarm()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Bist du sicher, dass die Ursache (z. B. Pellets nachgefüllt, Brennertopf gereinigt) behoben ist?\n\nDer Alarm wird auf der Ofenplatine quittiert und die Blockierung aufgehoben. Der Ofen wird dabei NICHT gezündet.")
        }
    }
    
    // MARK: - Wood Combustion Hero Card (Scheitholz-Betriebsführung)
    @ViewBuilder
    private var woodCombustionHeroCard: some View {
        let tracker = viewModel.woodTracker
        let phase = tracker.currentPhase
        
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 46, height: 46)
                    
                    Text("🪵")
                        .font(.system(size: 24))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Scheitholzbetrieb")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("10 kW Kombi")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                    
                    Text("Pelletförderung pausiert – 100% Holzverbrennung")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Phase indicator badge & text
            HStack(spacing: 8) {
                Image(systemName: phase.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(phase == .optimal ? .green : (phase == .coalsRefillReady ? .orange : .yellow))
                
                Text(phase.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(phase == .optimal ? .green : (phase == .coalsRefillReady ? .orange : .primary))
                
                Spacer()
                
                Text(String(format: "%.0f °C Abgas", viewModel.exhaustTemp))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            
            Text(phase.statusDescription)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Temperature bar with optimal range markings
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background track
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 8)
                        
                        // Optimal zone indicator (190°C - 320°C on a 0-400°C scale)
                        let minOptX = geo.size.width * (190.0 / 400.0)
                        let maxOptX = geo.size.width * (320.0 / 400.0)
                        Capsule()
                            .fill(Color.green.opacity(0.25))
                            .frame(width: maxOptX - minOptX, height: 8)
                            .offset(x: minOptX)
                        
                        // Current fill
                        let currentFraction = min(1.0, max(0.0, viewModel.exhaustTemp / 400.0))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: phase == .optimal ? [.orange, .green] : [.yellow, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * currentFraction, height: 8)
                    }
                }
                .frame(height: 8)
                
                HStack {
                    Text("100°C")
                    Spacer()
                    Text("190°C Optimal")
                        .foregroundColor(.green)
                    Spacer()
                    Text("320°C")
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary.opacity(0.8))
            }
            
            // Savings & Duration Footprint
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: "+%.2f kg", tracker.sessionSavedPelletsKg))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                        Text("Pellets gespart")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        let minutes = Int(tracker.currentWoodSessionDuration) / 60
                        let hours = minutes / 60
                        let displayTime = hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes) Min"
                        Text(displayTime)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                        Text("Holzlaufzeit")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .liquidGlass(
            cornerRadius: 22,
            tint: .orange,
            tintOpacity: 0.08,
            specularOpacity: 0.55
        )
    }
}

// MARK: - Lock Toggle Button (Icon-Only Liquid Glass)
struct LockToggleButton: View {
    @Binding var isLocked: Bool
    
    var body: some View {
        Button(action: {
            if isLocked {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isLocked = false
                }
            } else {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isLocked = true
                }
            }
        }) {
            ZStack {
                Circle()
                    .fill(isLocked ? Color.gray.opacity(0.14) : Color.green.opacity(0.18))
                    .frame(width: 38, height: 38)
                
                Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isLocked ? .secondary : .green)
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                isLocked ? Color.white.opacity(0.12) : Color.green.opacity(0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: isLocked ? Color.clear : Color.green.opacity(0.25), radius: 6, y: 2)
            .contentShape(Circle())
        }
        .buttonStyle(LiquidScaleButtonStyle())
        .accessibilityLabel(isLocked ? "Gesperrt" : "Entsperrt")
    }
}

// MARK: - TempCard (Liquid Glass Style)
struct TempCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    var showChevron: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(color.opacity(0.3), lineWidth: 1))
                    
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.system(size: 14, weight: .bold))
                }
                
                Spacer()
                
                if showChevron {
                    HStack(spacing: 3) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(color.opacity(0.85))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(color.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), color.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    )
                }
            }
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                    Text(unit)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Text(title)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 24, tint: color, tintOpacity: 0.04)
    }
}

// MARK: - Modern Action Button (Liquid Glass)
struct ModernActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .liquidGlass(cornerRadius: 20, tint: color, tintOpacity: 0.14, specularOpacity: 0.55)
            .foregroundStyle(color)
        }
        .buttonStyle(LiquidScaleButtonStyle())
    }
}

// MARK: - Status Pill
struct StatusPill: View {
    let name: String
    let isActive: Bool
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(name).font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
        .foregroundStyle(isActive ? .green : .secondary)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(
                isActive ? Color.green.opacity(0.3) : Color.white.opacity(0.15),
                lineWidth: 1
            )
        )
    }
}

// MARK: - Molten Liquid Glass Thermostat Dial (30pt Width, 260pt Height)
struct ThermostatDial: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onIDLE: () -> Void
    var onDrag: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            let strokeWidth: CGFloat = 30.0
            let paddingAmount: CGFloat = 26.0
            let availableWidth = min(geometry.size.width, geometry.size.height)
            let radius = (availableWidth - (paddingAmount * 2)) / 2
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let currentAngle = angleForValue(value)
            
            ZStack {
                // 1. Frosted Glass Trench (Hintergrund-Kanal mit 1pt Specular-Kante)
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        Color.black.opacity(0.06),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .padding(paddingAmount)
                    .rotationEffect(.degrees(90))
                
                // 2. Active Molten Liquid Arc (Flüssiges Glas-Glühen)
                Circle()
                    .trim(
                        from: 0.15,
                        to: CGFloat(0.15 + (0.7 * (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
                    )
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 1.0, green: 0.60, blue: 0.10),
                                Color(red: 0.98, green: 0.22, blue: 0.12)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .padding(paddingAmount)
                    .shadow(color: Color.orange.opacity(0.42), radius: 12, x: 0, y: 4)
                    .rotationEffect(.degrees(90))
                
                // 3. Central Temperature Readout (High-Impact Typography)
                VStack(spacing: -2) {
                    Text("SOLL-TEMPERATUR")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.4)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", value))
                            .font(.system(size: 60, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)
                        Text("°C")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                    
                    Text("Dielle 2ways Regelung")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.75))
                }
                
                // 4. Liquid Glass Droplet Knob (40pt mit Doppel-Lichtkante)
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .systemBackground))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white, Color.white.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 3)
                    
                    // Concentric Glowing Core
                    Circle()
                        .stroke(Color.orange.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 8, height: 8)
                        .shadow(color: Color.orange.opacity(0.8), radius: 3)
                }
                .position(
                    x: center.x + radius * cos(currentAngle),
                    y: center.y + radius * sin(currentAngle)
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            updateValue(with: gesture.location, in: geometry.size, radius: radius, center: center)
                            onDrag()
                        }
                        .onEnded { _ in
                            onIDLE()
                        }
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func angleForValue(_ val: Double) -> CGFloat {
        let percent = (val - range.lowerBound) / (range.upperBound - range.lowerBound)
        let startAngle = 144.0
        let totalSpan = 252.0
        return CGFloat((startAngle + (percent * totalSpan)) * .pi / 180)
    }
    
    private func updateValue(with location: CGPoint, in size: CGSize, radius: CGFloat, center: CGPoint) {
        let vector = CGVector(dx: location.x - center.x, dy: location.y - center.y)
        let angle = atan2(vector.dy, vector.dx)
        var degrees = angle * 180 / .pi
        if degrees < 0 { degrees += 360 }
        
        let start = 144.0
        let end = 396.0
        
        var normalized = degrees
        if normalized < start { normalized += 360 }
        
        if normalized >= start && normalized <= end {
            let percent = (normalized - start) / (end - start)
            let newValue = range.lowerBound + (percent * (range.upperBound - range.lowerBound))
            let rounded = (newValue * 2).rounded() / 2 // 0.5er Schritte
            if self.value != rounded {
                UISelectionFeedbackGenerator().selectionChanged()
                self.value = rounded
            }
        }
    }
}
