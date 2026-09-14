import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = StoveViewModel()
    @State private var showingSettings = false
    
    var body: some View {
        Group {
            if KeychainService.shared.load(key: "cloud_email") == nil {
                OnboardingView(viewModel: viewModel)
            } else {
                ZStack {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                    
                    RadialGradient(gradient: Gradient(colors: [Color.orange.opacity(0.12), .clear]), center: .topTrailing, startRadius: 5, endRadius: 500)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SmartHeat")
                                    .font(.system(.title, design: .rounded))
                                    .fontWeight(.bold)
                                
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(viewModel.socketService.isConnected ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    Text(viewModel.stoveStatus)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            
                            Button(action: { showingSettings = true }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 25)
                        .padding(.top, 20)
                        
                        DashboardView(viewModel: viewModel)
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(viewModel: viewModel)
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
    }
}

struct DashboardView: View {
    @ObservedObject var viewModel: StoveViewModel
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 25) {
                HStack(spacing: 15) {
                    TempCard(title: "Raum", value: String(format: "%.1f", viewModel.currentTemp), unit: "°C", icon: "house.fill", color: .orange)
                    TempCard(title: "Abgas", value: String(format: "%.0f", viewModel.exhaustTemp), unit: "°", icon: "thermometer.high", color: .red)
                }
                
                if viewModel.isWaterStove {
                    HStack(spacing: 15) {
                        TempCard(title: "Kessel", value: String(format: "%.1f", viewModel.waterTemp), unit: "°C", icon: "drop.fill", color: .blue)
                        TempCard(title: "Druck", value: String(format: "%.2f", viewModel.waterPressure), unit: "bar", icon: "gauge", color: .green)
                    }
                }
                
                if viewModel.isPelletTankEnabled {
                    PelletTankCard(pelletManager: viewModel.pelletManager, stoveStatus: viewModel.stoveStatus)
                }
                
                VStack(spacing: 20) {
                    HStack {
                        Text("Ziel-Temperatur")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.isTargetLocked.toggle()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: viewModel.isTargetLocked ? "lock.fill" : "lock.open.fill")
                                Text(viewModel.isTargetLocked ? "Gesperrt" : "Entsperrt")
                            }
                            .font(.caption.bold())
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(viewModel.isTargetLocked ? Color.gray.opacity(0.1) : Color.orange.opacity(0.15))
                            .foregroundColor(viewModel.isTargetLocked ? .secondary : .orange)
                            .clipShape(Capsule())
                        }
                    }
                    
                    ThermostatDial(value: $viewModel.targetTemp, range: 10...35) {
                        // onIDLE
                        if !viewModel.isTargetLocked {
                            viewModel.setTemperature(viewModel.targetTemp)
                        }
                    } onDrag: {
                        // onDrag
                        viewModel.triggerInteractionLock()
                    }
                    .frame(height: 200)
                    .opacity(viewModel.isTargetLocked ? 0.6 : 1.0)
                    .disabled(viewModel.isTargetLocked)
                }
                .padding(.vertical, 30)
                .padding(.horizontal, 20)
                .background(.thinMaterial)
                .cornerRadius(32)
                
                HStack(spacing: 15) {
                    ModernActionButton(title: "Einschalten", icon: "power", color: .green) {
                        viewModel.turnOn()
                    }
                    ModernActionButton(title: "Ausschalten", icon: "power", color: .red) {
                        viewModel.turnOff()
                    }
                }
                
                HStack(spacing: 15) {
                    StatusPill(name: "WLAN", isActive: viewModel.socketService.isConnected, icon: "wifi")
                    StatusPill(name: "BLE", isActive: viewModel.bleManager.connectedPeripheral != nil, icon: "antenna.radiowaves.left.and.right")
                    StatusPill(name: "Cloud", isActive: viewModel.authService.isAuthenticated, icon: "cloud.fill")
                }
            }
            .padding(25)
        }
        .onAppear {
            viewModel.refreshData()
        }
    }
}

// ... Rest of the components (TempCard, ModernActionButton, etc.) unchanged
struct TempCard: View {
    let title: String; let value: String; let unit: String; let icon: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).foregroundStyle(color).font(.headline)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(unit).font(.system(.title2, design: .rounded)).fontWeight(.semibold).foregroundStyle(.secondary)
                }
                Text(title).font(.caption).fontWeight(.bold).foregroundStyle(.secondary).textCase(.uppercase)
            }
        }
        .padding(20).frame(maxWidth: .infinity).background(.thinMaterial).cornerRadius(24)
    }
}

struct ModernActionButton: View {
    let title: String; let icon: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon).font(.title2).fontWeight(.semibold)
                Text(title).font(.footnote).fontWeight(.bold)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18).background(color.opacity(0.12)).foregroundStyle(color).cornerRadius(20)
        }
    }
}

struct StatusPill: View {
    let name: String; let isActive: Bool; let icon: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(name).font(.system(size: 10, weight: .bold))
        }
        .padding(.vertical, 6).padding(.horizontal, 12).background(isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.1)).foregroundStyle(isActive ? .green : .secondary).clipShape(Capsule())
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: () -> Void
    var body: some View {
        Slider(value: $value, in: range, step: 0.5) { _ in onEditingChanged() }.accentColor(.orange)
    }
}

struct ThermostatDial: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onIDLE: () -> Void
    var onDrag: () -> Void
    
    @State private var angleValue: Double = 0
    
    var body: some View {
        ZStack {
            // Hintergrund-Bogen
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.black.opacity(0.05), style: StrokeStyle(lineWidth: 25, lineCap: .round))
                .rotationEffect(.degrees(90))
            
            // Aktiver Bogen
            Circle()
                .trim(from: 0.15, to: CGFloat(0.15 + (0.7 * (value - range.lowerBound) / (range.upperBound - range.lowerBound))))
                .stroke(
                    LinearGradient(gradient: Gradient(colors: [.orange, .red]), startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 25, lineCap: .round)
                )
                .shadow(color: .orange.opacity(0.3), radius: 10, x: 0, y: 5)
                .rotationEffect(.degrees(90))
            
            // Temperatur-Anzeige
            VStack(spacing: -5) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                Text("°C")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            // Der Slider-Knopf
            GeometryReader { geometry in
                let radius = geometry.size.width / 2
                let currentAngle = angleForValue(value)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 35, height: 35)
                    .shadow(radius: 5)
                    .overlay(Circle().stroke(Color.orange, lineWidth: 2))
                    .offset(x: radius * cos(currentAngle), y: radius * sin(currentAngle))
                    .position(x: radius, y: radius)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                updateValue(with: gesture.location, in: geometry.size)
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
        // 0.15 bis 0.85 von 360 Grad, rotiert um 90 Grad
        let startAngle = 144.0 // 0.4 * 360 - korrigiert für Halbkreis unten offen
        let totalSpan = 252.0
        return CGFloat((startAngle + (percent * totalSpan)) * .pi / 180)
    }
    
    private func updateValue(with location: CGPoint, in size: CGSize) {
        let vector = CGVector(dx: location.x - size.width/2, dy: location.y - size.height/2)
        let angle = atan2(vector.dy, vector.dx)
        var degrees = angle * 180 / .pi
        if degrees < 0 { degrees += 360 }
        
        // Wir mappen die Grade (ca. 144 bis 396) zurück auf den Range
        let start = 144.0
        let end = 396.0
        
        var normalized = degrees
        if normalized < start { normalized += 360 }
        
        if normalized >= start && normalized <= end {
            let percent = (normalized - start) / (end - start)
            let newValue = range.lowerBound + (percent * (range.upperBound - range.lowerBound))
            self.value = (newValue * 2).rounded() / 2 // 0.5er Schritte
        }
    }
}
