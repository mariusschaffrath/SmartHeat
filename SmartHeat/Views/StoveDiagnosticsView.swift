//
//  StoveDiagnosticsView.swift
//  SmartHeat
//
//  Motherboard Diagnostics & Maintenance Inspection View with Apple Liquid Glass styling.
//

import SwiftUI

struct StoveDiagnosticsView: View {
    @ObservedObject var viewModel: StoveViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingResetAlert = false
    
    private var diagnostics: StoveDiagnostics {
        viewModel.diagnostics
    }
    
    init(viewModel: StoveViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            
            // Subtle ambient backdrop
            RadialGradient(
                gradient: Gradient(colors: [
                    diagnostics.isServiceDue ? Color.red.opacity(0.12) :
                    diagnostics.isServiceImminent ? Color.orange.opacity(0.1) : Color.blue.opacity(0.06),
                    .clear
                ]),
                center: .topTrailing,
                startRadius: 20,
                endRadius: 550
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // 1. Service Hero Card
                    serviceInspectionHeroCard
                    
                    // 2. Operational Metrics Grid
                    metricsGridCard
                    
                    // 3. Technical Hardware & Board Details
                    hardwareDetailsCard
                    
                    // 4. Inspection & Maintenance Checklist
                    maintenanceChecklistCard
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Betriebsdaten & Wartung")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Wartungsintervall zurücksetzen?", isPresented: $showingResetAlert) {
            Button("Abbrechen", role: .cancel) {}
            Button("Wartung bestätigen", role: .destructive) {
                viewModel.resetServiceMaintenance()
            }
        } message: {
            Text("Möchtest du die 2.000-Stunden-Inspektion als durchgeführt markieren? Der Intervallzähler wird ab den aktuellen \(diagnostics.totalOperatingHours) Betriebsstunden für die nächsten 2.000 Stunden neu gestartet.")
        }
    }
    
    // MARK: - Service Hero Card
    private var serviceInspectionHeroCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Wartungsintervall (2.000 h)")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        serviceStatusBadge
                    }
                    
                    if diagnostics.isServiceDue {
                        Text("Inspektion fällig!")
                            .font(.title2.bold())
                            .foregroundColor(.red)
                    } else if diagnostics.isServiceImminent {
                        Text("Noch \(diagnostics.hoursUntilService) Stunden")
                            .font(.title2.bold())
                            .foregroundColor(.orange)
                    } else {
                        Text("Noch \(diagnostics.hoursUntilService) Stunden")
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                    }
                    
                    Text("Standard-Inspektion alle 2.000 Betriebsstunden empfohlen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Progress Circle
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 8)
                        .frame(width: 68, height: 68)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(diagnostics.serviceProgress))
                        .stroke(
                            diagnostics.isServiceDue ? Color.red :
                            diagnostics.isServiceImminent ? Color.orange : Color.green,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 68, height: 68)
                    
                    Text("\(Int(diagnostics.serviceProgress * 100))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
            }
            
            // Linear Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(
                            diagnostics.isServiceDue ? LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing) :
                            diagnostics.isServiceImminent ? LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing) :
                            LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * CGFloat(diagnostics.serviceProgress), height: 8)
                }
            }
            .frame(height: 8)
            
            // Letzte Wartung Info & Quittierungs-Button
            Divider().opacity(0.15)
            
            if let lastDate = diagnostics.lastServiceDate {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Letzte Wartung: \(lastDate.formatted(date: .numeric, time: .omitted)) (bei \(diagnostics.lastServiceOperatingHours) h)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingResetAlert = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.subheadline.bold())
                    Text(diagnostics.isServiceDue ? "2.000h Wartung jetzt quittieren" : "Wartungsintervall zurücksetzen")
                        .font(.subheadline.bold())
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(diagnostics.isServiceDue ? Color.red.opacity(0.85) : Color.blue.opacity(0.75))
                )
            }
            .buttonStyle(LiquidScaleButtonStyle())
        }
        .padding(18)
        .liquidGlass(
            cornerRadius: 22,
            tint: diagnostics.isServiceDue ? .red : (diagnostics.isServiceImminent ? .orange : .green),
            tintOpacity: 0.08,
            specularOpacity: 0.55
        )
    }
    
    private var serviceStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(diagnostics.isServiceDue ? Color.red : (diagnostics.isServiceImminent ? Color.orange : Color.green))
                .frame(width: 6, height: 6)
            Text(diagnostics.isServiceDue ? "Fällig" : (diagnostics.isServiceImminent ? "Bald fällig" : "OK"))
                .font(.caption2.bold())
                .foregroundColor(diagnostics.isServiceDue ? .red : (diagnostics.isServiceImminent ? .orange : .green))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            (diagnostics.isServiceDue ? Color.red : (diagnostics.isServiceImminent ? Color.orange : Color.green))
                .opacity(0.12)
        )
        .clipShape(Capsule())
    }
    
    // MARK: - Metrics 2x2 Grid
    private var metricsGridCard: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            metricTile(
                title: "Gesamtlaufzeit",
                value: "\(diagnostics.totalOperatingHours) h",
                icon: "clock.arrow.circlepath",
                tintColor: .blue
            )
            
            metricTile(
                title: "Heizzeit (P1–P5)",
                value: "\(diagnostics.heatingHours) h",
                icon: "flame.fill",
                tintColor: .orange
            )
            
            metricTile(
                title: "Erfolgreiche Zündungen",
                value: "\(diagnostics.ignitionCount)",
                icon: "bolt.fill",
                tintColor: .yellow
            )
            
            metricTile(
                title: "Rezeptur-Modus",
                value: "Profil #\(diagnostics.recipeNumber)",
                icon: "slider.horizontal.3",
                tintColor: .purple
            )
        }
    }
    
    private func metricTile(title: String, value: String, icon: String, tintColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(tintColor)
                    .frame(width: 32, height: 32)
                    .background(tintColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundColor(.primary)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 18, tint: tintColor, tintOpacity: 0.04, specularOpacity: 0.4)
    }
    
    // MARK: - Technical Hardware Details
    private var hardwareDetailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Platinen-Spezifikation", systemImage: "cpu.fill")
                .font(.headline)
                .fontWeight(.bold)
            
            Divider().opacity(0.3)
            
            detailRow(title: "Steuerungs-Platine", value: diagnostics.boardCode)
            detailRow(title: "Firmware-Version", value: diagnostics.firmwareVersion)
            detailRow(title: "Protokoll-Standard", value: "Dielle 2ways (SERVIZI2W)")
            detailRow(title: "Ofenmodell", value: "Dielle Ghibli Hybrid Kombi 10 kW")
            detailRow(title: "Feuerungssystem", value: "Hybrid-Automatik (Pellet & Holz)")
        }
        .padding(16)
        .liquidGlass(cornerRadius: 22, tint: .clear, tintOpacity: 0.05, specularOpacity: 0.4)
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Maintenance Checklist
    private var maintenanceChecklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Empfohlene Wartungsschritte", systemImage: "checklist")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            VStack(spacing: 10) {
                checklistRow(title: "Brennraum & Aschelade", desc: "Regelmäßig absaugen und Flugasche entfernen.")
                checklistRow(title: "Dichtungsbänder prüfen", desc: "Dichtigkeit der Tür- und Scheibendichtungen kontrollieren.")
                checklistRow(title: "Wärmetauscher reinigen", desc: "Reinigungsfedern betätigen und Kanäle freihalten.")
                checklistRow(title: "Kaminrohr & T-Stück", desc: "Vor jeder Heizperiode Rußablagerungen entfernen.")
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 22, tint: .clear, tintOpacity: 0.05, specularOpacity: 0.35)
    }
    
    private func checklistRow(title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.subheadline)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
