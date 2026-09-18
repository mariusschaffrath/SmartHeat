//
//  RoomTempDetailView.swift
//  SmartHeat
//
//  Interactive Chart Sheet for Room Temperature:
//  Displays Today (Day), Last 7 Days, and Monthly Average in a combined Swift Chart.
//

import SwiftUI
import Charts

public struct RoomTempDetailView: View {
    @ObservedObject var historyManager: TemperatureHistoryManager
    let currentTemp: Double
    let targetTemp: Double
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRange: TimeRange = .today
    @State private var selectedPoint: TemperaturePoint? = nil
    
    public enum TimeRange: String, CaseIterable, Identifiable {
        case today = "Heute"
        case week = "7 Tage"
        case month = "30 Tage"
        
        public var id: String { rawValue }
    }
    
    public init(historyManager: TemperatureHistoryManager, currentTemp: Double, targetTemp: Double) {
        self.historyManager = historyManager
        self.currentTemp = currentTemp
        self.targetTemp = targetTemp
    }
    
    private var displayedPoints: [TemperaturePoint] {
        switch selectedRange {
        case .today:
            return historyManager.todayRoomPoints
        case .week:
            return historyManager.last7DaysRoomPoints
        case .month:
            return historyManager.last30DaysRoomPoints
        }
    }
    
    private var yMin: Double {
        let minVal = displayedPoints.map(\.temperature).min() ?? 19.0
        let monthly = historyManager.monthlyRoomAvg
        return max(15.0, min(minVal, monthly) - 1.0)
    }
    
    private var yMax: Double {
        let maxVal = displayedPoints.map(\.temperature).max() ?? 23.0
        let target = targetTemp > 0 ? targetTemp : 22.0
        let monthly = historyManager.monthlyRoomAvg
        return max(max(maxVal, target), monthly) + 1.2
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                
                RadialGradient(
                    gradient: Gradient(colors: [Color.orange.opacity(0.15), .clear]),
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
                            ForEach(TimeRange.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        
                        // MARK: - Swift Chart Card
                        chartCard
                        
                        // MARK: - Statistics Metric Grid
                        statisticsGrid
                        
                        // MARK: - Ambient Comfort Advice Card
                        comfortInsightCard
                        
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
                Image(systemName: "house.fill")
                    .foregroundColor(.orange)
                    .font(.subheadline)
                Text("Raumtemperatur Verlauf")
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
                Text(String(format: "%.1f", currentTemp))
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                Text("°C")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            let diff = currentTemp - targetTemp
            HStack(spacing: 6) {
                Image(systemName: diff >= 0 ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                    .foregroundColor(diff >= 0 ? .green : .orange)
                    .font(.caption)
                
                Text(diff >= 0 ?
                     String(format: "Zieltemperatur (%.1f °C) erreicht", targetTemp) :
                     String(format: "%.1f °C unter Solltemperatur (%.1f °C)", abs(diff), targetTemp))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
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
                Text("Temperaturkurve & Monatsdurchschnitt")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                
                if let selected = selectedPoint {
                    Text(String(format: "%.1f °C", selected.temperature))
                        .font(.subheadline.bold())
                        .foregroundColor(.orange)
                }
            }
            
            if let selected = selectedPoint {
                Text(selected.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(selectedRange == .today ? "Heutiger Tagesverlauf mit Monats-Referenz" :
                     (selectedRange == .week ? "Verlauf der letzten 7 Tage" : "Historie der letzten 30 Tage"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Chart {
                // 1. Monatsdurchschnitt RuleMark (Vom User explizit im selben Graph gewünscht)
                RuleMark(y: .value("Monatsdurchschnitt", historyManager.monthlyRoomAvg))
                    .foregroundStyle(Color.purple.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(String(format: "Ø Monat %.1f°C", historyManager.monthlyRoomAvg))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                    }
                
                // 2. Solltemperatur Referenzlinie
                RuleMark(y: .value("Solltemperatur", targetTemp))
                    .foregroundStyle(Color.orange.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                
                // 3. Kurvenverlauf (Area + Line)
                ForEach(displayedPoints) { point in
                    AreaMark(
                        x: .value("Zeit", point.date),
                        yStart: .value("Basis", yMin),
                        yEnd: .value("Temperatur", point.temperature)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.32), Color.orange.opacity(0.02)],
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
                    .foregroundStyle(Color.orange)
                }
            }
            .chartYScale(domain: yMin...yMax)
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
                legendItem(color: .orange, label: "Gemessen")
                legendItem(color: .purple, label: "Monatsdurchschnitt", isDashed: true)
                legendItem(color: .orange.opacity(0.5), label: "Zieltemperatur", isDashed: true)
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
    
    // MARK: - Statistics Metric Grid
    
    private var statisticsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statCard(
                    title: "Tages-Schnitt",
                    value: String(format: "%.1f °C", historyManager.todayRoomAvg),
                    icon: "calendar",
                    color: .orange
                )
                statCard(
                    title: "7-Tage-Schnitt",
                    value: String(format: "%.1f °C", historyManager.last7DaysRoomAvg),
                    icon: "chart.bar.fill",
                    color: .blue
                )
            }
            
            HStack(spacing: 12) {
                statCard(
                    title: "Monatsdurchschnitt",
                    value: String(format: "%.1f °C", historyManager.monthlyRoomAvg),
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    color: .purple
                )
                statCard(
                    title: "Min / Max Heute",
                    value: String(format: "%.1f – %.1f", historyManager.todayRoomMin, historyManager.todayRoomMax),
                    icon: "arrow.up.and.down.circle",
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
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(18)
    }
    
    // MARK: - Ambient Comfort Advice Card
    
    private var comfortInsightCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkles")
                    .foregroundColor(.orange)
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Thermischer Komfort")
                    .font(.subheadline)
                    .fontWeight(.bold)
                
                let diff = currentTemp - historyManager.monthlyRoomAvg
                let note = abs(diff) < 0.5 ?
                    "Aktuelle Temperatur entspricht exakt deinem Monatsmittelwert." :
                    (diff > 0 ?
                     String(format: "Aktuell %.1f °C über deinem Monatsdurchschnitt.", diff) :
                     String(format: "Aktuell %.1f °C unter deinem Monatsdurchschnitt.", abs(diff)))
                
                Text(note)
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
