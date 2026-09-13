import SwiftUI

struct PelletTankCard: View {
    @ObservedObject var pelletManager: PelletTankManager
    let stoveStatus: String
    
    @State private var showingAdjustSheet: Bool = false
    @State private var tempAdjustmentLevel: Double = 0.0
    
    var progressColor: Color {
        if pelletManager.fillPercentage > 40 {
            return .green
        } else if pelletManager.fillPercentage > 20 {
            return .orange
        } else {
            return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "fuelpump.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pellet-Tank")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("Dielle Ghibli Kombi 10 kW")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if pelletManager.isLowPellet {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Fast leer")
                    }
                    .font(.caption2.bold())
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .clipShape(Capsule())
                }
                
                Button(action: {
                    tempAdjustmentLevel = pelletManager.currentLevel
                    showingAdjustSheet = true
                }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.gray.opacity(0.12))
                        .clipShape(Circle())
                }
            }
            
            // Füllstand Werte & Prozent
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", pelletManager.currentLevel))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("/ \(String(format: "%.0f", pelletManager.tankCapacity)) kg")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(String(format: "%.0f %%", pelletManager.fillPercentage))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(progressColor)
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 12)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [progressColor.opacity(0.8), progressColor]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * CGFloat(min(1.0, pelletManager.fillPercentage / 100.0))), height: 12)
                        .animation(.easeInOut(duration: 0.3), value: pelletManager.fillPercentage)
                }
            }
            .frame(height: 12)
            
            // Status- & Verbrauchshinweis
            HStack(spacing: 6) {
                if pelletManager.isWoodModeActive {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(.green)
                    Text("Holzbetrieb aktiv (Pellet-Verbrauch pausiert)")
                        .font(.caption)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                } else if stoveStatus.contains("Betrieb") || stoveStatus.contains("Modulation") {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("Stufe P\(pelletManager.currentPowerLevel) (\(String(format: "%.2f", pelletManager.currentHourlyConsumption)) kg/h) • Noch ca. \(String(format: "%.1f", pelletManager.remainingHours)) Std.")
                        .font(.caption)
                        .foregroundColor(.primary)
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.secondary)
                    let standbyForecast = pelletManager.currentLevel / 0.95
                    Text("Ofen aus • Reicht für ca. \(String(format: "%.0f", standbyForecast)) Std. auf Stufe P2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
            
            Divider()
            
            // Quick-Action Buttons
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation {
                        pelletManager.refillBag()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("+1 Sack (\(String(format: "%.0f", pelletManager.bagWeight)) kg)")
                    }
                    .font(.footnote.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.12))
                    .foregroundColor(.orange)
                    .cornerRadius(12)
                }
                .disabled(pelletManager.currentLevel >= pelletManager.tankCapacity)
                .opacity(pelletManager.currentLevel >= pelletManager.tankCapacity ? 0.5 : 1.0)
                
                Button(action: {
                    withAnimation {
                        pelletManager.refillFull()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                        Text("Voll (\(String(format: "%.0f", pelletManager.tankCapacity)) kg)")
                    }
                    .font(.footnote.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.12))
                    .foregroundColor(.green)
                    .cornerRadius(12)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .cornerRadius(24)
        .sheet(isPresented: $showingAdjustSheet) {
            NavigationView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Füllstand manuell korrigieren")
                            .font(.headline)
                        Text("Stelle den aktuellen Tankinhalt exakt ein, falls du nur einen Teil nachgefüllt hast.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("Tankinhalt:")
                            Spacer()
                            Text(String(format: "%.1f kg (%.0f %%)", tempAdjustmentLevel, (tempAdjustmentLevel / pelletManager.tankCapacity) * 100))
                                .font(.system(.title3, design: .rounded).bold())
                                .foregroundColor(.orange)
                        }
                        
                        Slider(value: $tempAdjustmentLevel, in: 0...pelletManager.tankCapacity, step: 0.5)
                            .accentColor(.orange)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(16)
                    
                    Spacer()
                }
                .padding(20)
                .navigationTitle("Pellet-Füllstand")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") {
                            showingAdjustSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") {
                            pelletManager.setLevel(kg: tempAdjustmentLevel)
                            showingAdjustSheet = false
                        }
                        .bold()
                    }
                }
            }
            .presentationDetents([.height(280)])
        }
    }
}
