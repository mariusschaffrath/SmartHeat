import ActivityKit
import WidgetKit
import SwiftUI

public struct StoveLiveActivity: Widget {
    public init() {}
    
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: StoveActivityAttributes.self) { context in
            // ==========================================
            // LOCKSCREEN / BANNER VIEW
            // ==========================================
            VStack(alignment: .leading, spacing: 10) {
                // Header: Ofenname & Phase
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(context.state.isIgnition ? Color.orange.opacity(0.2) : Color.cyan.opacity(0.2))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: context.state.isIgnition ? "flame.fill" : "fanblades.fill")
                            .font(.title3)
                            .foregroundColor(context.state.isIgnition ? .orange : .cyan)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.phaseName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(context.state.statusDetail)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Abgastemperatur Badge
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.high")
                                .font(.caption2)
                                .foregroundColor(.red)
                            Text("\(Int(context.state.exhaustTemp))°C")
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        Text("Abgas")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                }
                
                // Countdown & Progress
                VStack(spacing: 6) {
                    ProgressView(value: context.state.progress)
                        .tint(context.state.isIgnition ? .orange : .cyan)
                    
                    HStack {
                        Text("Ziel: \(context.state.targetPhaseName)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.caption2)
                                .foregroundColor(context.state.isIgnition ? .orange : .cyan)
                            Text(timerInterval: context.state.startDate...context.state.estimatedEndDate, countsDown: true)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                    }
                }
                
                // Footer: Raum- und Solltemperatur
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "Raum: %.1f°C", context.state.roomTemp))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text(String(format: "Soll: %.1f°C", context.state.targetTemp))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    
                    if context.state.isWoodActive {
                        HStack(spacing: 4) {
                            Image(systemName: "leaf.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("Scheitholz")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    } else if context.state.powerLevel > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text("P\(context.state.powerLevel)")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    Spacer()
                }
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.85))
            
        } dynamicIsland: { context in
            // ==========================================
            // DYNAMIC ISLAND VIEW
            // ==========================================
            DynamicIsland {
                // Expanded Leading
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.isIgnition ? "flame.fill" : "fanblades.fill")
                            .foregroundColor(context.state.isIgnition ? .orange : .cyan)
                        Text(context.state.phaseName)
                            .font(.subheadline)
                            .fontWeight(.bold)
                    }
                }
                
                // Expanded Trailing
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.high")
                            .foregroundColor(.red)
                        Text("\(Int(context.state.exhaustTemp))°C")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                    }
                }
                
                // Expanded Bottom
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: context.state.progress)
                            .tint(context.state.isIgnition ? .orange : .cyan)
                        
                        HStack {
                            Text(context.state.statusDetail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(timerInterval: context.state.startDate...context.state.estimatedEndDate, countsDown: true)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(context.state.isIgnition ? .orange : .cyan)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isIgnition ? "flame.fill" : "fanblades.fill")
                    .foregroundColor(context.state.isIgnition ? .orange : .cyan)
            } compactTrailing: {
                Text("\(Int(context.state.exhaustTemp))°")
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            } minimal: {
                Image(systemName: context.state.isIgnition ? "flame.fill" : "fanblades.fill")
                    .foregroundColor(context.state.isIgnition ? .orange : .cyan)
            }
            .widgetURL(URL(string: "smartheat://stove"))
            .keylineTint(context.state.isIgnition ? .orange : .cyan)
        }
    }
}
