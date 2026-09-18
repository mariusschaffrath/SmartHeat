//
//  ExhaustTempDetailView.swift
//  SmartHeat
//
//  Interactive Chart Sheet for Stove Exhaust Temperature (Abgastemperatur):
//  Displays Combustion curve, Burn cycles, and Technical Operating Phases.
//

import SwiftUI
import Charts

public struct ExhaustTempDetailView: View {
    @ObservedObject var historyManager: TemperatureHistoryManager
    let currentExhaustTemp: Double
    let stoveStatus: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRange: ExhaustTimeRange = .today
    @State private var selectedPoint: TemperaturePoint? = nil
    
    public enum ExhaustTimeRange: String, CaseIterable, Identifiable {
        case today = "Heute"
        case week = "7 Tage"
        
        public var id: String { rawValue }
    }
    
    public init(historyManager: TemperatureHistoryManager, currentExhaustTemp: Double, stoveStatus: String) {
        self.historyManager = historyManager
        self.currentExhaustTemp = currentExhaustTemp
        self.stoveStatus = stoveStatus
    }
    
    private var displayedPoints: [TemperaturePoint] {
        switch selectedRange {
        case .today:
            return historyManager.todayExhaustPoints
        case .week:
            return historyManager.last7DaysExhaustPoints
        }
    }
    
    private var yMax: Double {
        let maxVal = displayedPoints.map(\.temperature).max() ?? 200.0
        return max(220.0, maxVal + 20.0)
    }
    
    private var combustionPhase: (title: String, color: Color, icon: String) {
        if currentExhaustTemp < 45.0 {
            return ("Aus / Standby", .secondary, "power")
        } else if currentExhaustTemp < 95.0 {
            return ("Zündung / Start", .orange, "flame")
        } else if currentExhaustTemp <= 175.0 {
            return ("Optimaler Heizbetrieb", .green, "flame.fill")
        } else {
            return ("Hohe Modulation / Vollast", .red, "bolt.fill")
        }
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                
                RadialGradient(
                    gradient: Gradient(colors: [Color.red.opacity(0.15), .clear]),
                    center: .topTrailing,
                    startRadius: 5,
                    endRadius: 450
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        
                        // MARK: - Header Hero Card
                        headerHeroCard
                        
                        // MARK: - Time Range Picker
                        Picker("Zeitraum", selection: $selectedRange) {
                            ForEach(ExhaustTimeRange.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        
                        // MARK: - Swift Chart Card
                        chartCard
                        
                        // MARK: - Statistics Grid
                        statisticsGrid
                        
                        // MARK: - Efficiency & Technical Insight Card
                        technicalInsightCard
                        
                        Spacer(minLength: 30)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Header Hero Card
    
    private var headerHeroCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "thermometer.high")
                    .foregroundColor(.red)
                    .font(.subheadline)
                Text("Abgastemperatur Verlauf")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                if historyManager.isHomeAssistantBacked {
                    HStack(spacing: 3) {
                        Image(systemName: "server.rack")
                        Text("24/7 HA")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
                }
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", currentExhaustTemp))
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                Text("°C")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 6) {
                Image(systemName: combustionPhase.icon)
                    .foregroundColor(combustionPhase.color)
                    .font(.caption)
                
                Text(combustionPhase.title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(combustionPhase.color)
                
                Text("• Status: \(stoveStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(combustionPhase.color.opacity(0.12))
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Swift Chart Card
    
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Abgas- & Verbrennungskurve")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                
                if let selected = selectedPoint {
                    Text(String(format: "%.0f °C", selected.temperature))
                        .font(.subheadline.bold())
                        .foregroundColor(.red)
                }
            }
            
            if let selected = selectedPoint {
                Text(selected.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(selectedRange == .today ? "Verlauf des heutigen Brennzyklus" : "Historische Abgaswerte der letzten 7 Tage")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Chart {
                // 1. Nennbetrieb-Zielzone (140°C)
                RuleMark(y: .value("Nennbetrieb", 140.0))
                    .foregroundStyle(Color.green.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Optimal 140°C")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .cornerRadius(5)
                    }
                
                // 2. Volllast-Schwelle (180°C)
                RuleMark(y: .value("Modulationsschwelle", 180.0))
                    .foregroundStyle(Color.red.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                
                // 3. Area + Line Curve
                ForEach(displayedPoints) { point in
                    AreaMark(
                        x: .value("Zeit", point.date),
                        yStart: .value("Basis", 20.0),
                        yEnd: .value("Temperatur", point.temperature)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.red.opacity(0.35), Color.orange.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    LineMark(
                        x: .value("Zeit", point.date),
                        y: .value("Temperatur", point.temperature)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                
                // 4. Interaktiver Scrubber Punkt
                if let selected = selectedPoint {
                    RuleMark(x: .value("Ausgewählt", selected.date))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    
                    PointMark(
                        x: .value("Zeit", selected.date),
                        y: .value("Temperatur", selected.temperature)
                    )
                    .symbolSize(75)
                    .foregroundStyle(Color.red)
                }
            }
            .chartYScale(domain: 20...yMax)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel(format: selectedRange == .today ?
                                   .dateTime.hour() :
                                   .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel {
                        if let d = val.as(Double.self) {
                            Text(String(format: "%.0f°", d))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let originX = geometry[proxy.plotAreaFrame].origin.x
                                    let xPos = value.location.x - originX
                                    if let date: Date = proxy.value(atX: xPos) {
                                        selectedPoint = displayedPoints.min(by: {
                                            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                        })
                                    }
                                }
                                .onEnded { _ in
                                    selectedPoint = nil
                                }
                        )
                }
            }
            .frame(height: 230)
            
            // Legende
            HStack(spacing: 16) {
                legendItem(color: .red, label: "Abgastemperatur")
                legendItem(color: .green, label: "Optimalbereich (140°C)", isDashed: true)
                legendItem(color: .red.opacity(0.5), label: "Volllast (180°C)", isDashed: true)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .cornerRadius(28)
        .padding(.horizontal, 20)
    }
    
    private func legendItem(color: Color, label: String, isDashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            if isDashed {
                HStack(spacing: 2) {
                    Circle().fill(color).frame(width: 3, height: 3)
                    Circle().fill(color).frame(width: 3, height: 3)
                    Circle().fill(color).frame(width: 3, height: 3)
                }
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Statistics Grid
    
    private var statisticsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statCard(
                    title: "Tages-Peak (Max)",
                    value: String(format: "%.0f °C", historyManager.exhaustPeakToday),
                    icon: "arrow.up.right.circle.fill",
                    color: .red
                )
                statCard(
                    title: "Betriebs-Schnitt",
                    value: String(format: "%.0f °C", historyManager.exhaustOperatingAvg),
                    icon: "flame.fill",
                    color: .orange
                )
            }
            
            HStack(spacing: 12) {
                statCard(
                    title: "Aktuelle Phase",
                    value: combustionPhase.title,
                    icon: combustionPhase.icon,
                    color: combustionPhase.color
                )
                statCard(
                    title: "Abgas-Sicherheit",
                    value: "< 250 °C (Norm)",
                    icon: "shield.checkerboard",
                    color: .green
                )
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(18)
    }
    
    // MARK: - Efficiency & Technical Insight Card
    
    private var technicalInsightText: String {
        if currentExhaustTemp < 45.0 {
            return "Der Ofen ist abgekühlt. Wärmetauscher und Kaminzug sind im Ruhezustand."
        } else if currentExhaustTemp < 100.0 {
            return "Anheizphase aktiv. Glühzünder und Rauchgasgebläse etablieren die Grundflamme."
        } else if currentExhaustTemp <= 175.0 {
            return "Hervorragender Wirkungsgrad. Die Wärme wird optimal an Raum und Wärmetauscher übertragen."
        } else {
            return "Modulationsbetrieb aktiv. Ofen regelt Pelletzufuhr herunter, um Überhitzung zu vermeiden."
        }
    }
    
    private var technicalInsightCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "gauge.badge.plus")
                    .foregroundColor(.red)
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Verbrennungs-Effizienz")
                    .font(.subheadline)
                    .fontWeight(.bold)
                
                Text(technicalInsightText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .padding(.horizontal, 20)
    }
}
