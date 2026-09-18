//
//  TemperatureHistoryManager.swift
//  SmartHeat
//
//  Telemetry history and statistical calculations for Room & Exhaust temperatures.
//  Provides 24h day curves, 7-day trends, and 30-day monthly averages for Swift Charts.
//

import Foundation
import SwiftUI
import Combine

public struct TemperaturePoint: Identifiable, Codable, Equatable {
    public let id: UUID
    public let date: Date
    public let temperature: Double
    
    public init(id: UUID = UUID(), date: Date, temperature: Double) {
        self.id = id
        self.date = date
        self.temperature = temperature
    }
}

@MainActor
public class TemperatureHistoryManager: ObservableObject {
    public static let shared = TemperatureHistoryManager()
    
    @Published public var roomTempHistory: [TemperaturePoint] = []
    @Published public var exhaustTempHistory: [TemperaturePoint] = []
    @Published public var isHomeAssistantBacked: Bool = false
    @Published public var lastHASyncDate: Date? = nil
    
    private let roomHistoryKey = "smartheat_room_temp_history"
    private let exhaustHistoryKey = "smartheat_exhaust_temp_history"
    private var lastRecordedDate: Date = .distantPast
    private let fileQueue = DispatchQueue(label: "de.marius.smartheat.historyQueue", qos: .utility)
    
    private var roomHistoryFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("smartheat_room_history.json")
    }
    
    private var exhaustHistoryFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("smartheat_exhaust_history.json")
    }
    
    public init() {
        loadHistory()
    }
    
    /// Replaces/merges synthetic or partial local data with 24/7 verified database history from Home Assistant
    public func updateWithHomeAssistantData(roomPoints: [TemperaturePoint], exhaustPoints: [TemperaturePoint]) {
        guard !roomPoints.isEmpty || !exhaustPoints.isEmpty else { return }
        
        if !roomPoints.isEmpty {
            self.roomTempHistory = roomPoints
        }
        if !exhaustPoints.isEmpty {
            self.exhaustTempHistory = exhaustPoints
        }
        
        self.isHomeAssistantBacked = true
        self.lastHASyncDate = Date()
        saveHistory()
    }
    
    // MARK: - Filtered Series for Room Temp
    
    public var todayRoomPoints: [TemperaturePoint] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let points = roomTempHistory.filter { $0.date >= startOfDay }
        return points.isEmpty ? roomTempHistory.suffix(24) : points
    }
    
    public var last7DaysRoomPoints: [TemperaturePoint] {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let points = roomTempHistory.filter { $0.date >= sevenDaysAgo }
        return points.isEmpty ? roomTempHistory : points
    }
    
    public var last30DaysRoomPoints: [TemperaturePoint] {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let points = roomTempHistory.filter { $0.date >= thirtyDaysAgo }
        return points.isEmpty ? roomTempHistory : points
    }
    
    // MARK: - Room Temperature Statistics
    
    public var todayRoomAvg: Double {
        let pts = todayRoomPoints
        guard !pts.isEmpty else { return 21.4 }
        return pts.map(\.temperature).reduce(0.0, +) / Double(pts.count)
    }
    
    public var last7DaysRoomAvg: Double {
        let pts = last7DaysRoomPoints
        guard !pts.isEmpty else { return 21.2 }
        return pts.map(\.temperature).reduce(0.0, +) / Double(pts.count)
    }
    
    public var monthlyRoomAvg: Double {
        let pts = last30DaysRoomPoints
        guard !pts.isEmpty else { return 21.3 }
        return pts.map(\.temperature).reduce(0.0, +) / Double(pts.count)
    }
    
    public var todayRoomMin: Double {
        let pts = todayRoomPoints
        guard !pts.isEmpty else { return 19.8 }
        return pts.map(\.temperature).min() ?? 19.8
    }
    
    public var todayRoomMax: Double {
        let pts = todayRoomPoints
        guard !pts.isEmpty else { return 22.8 }
        return pts.map(\.temperature).max() ?? 22.8
    }
    
    // MARK: - Filtered Series for Exhaust Temp
    
    public var todayExhaustPoints: [TemperaturePoint] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let points = exhaustTempHistory.filter { $0.date >= startOfDay }
        return points.isEmpty ? exhaustTempHistory.suffix(24) : points
    }
    
    public var last7DaysExhaustPoints: [TemperaturePoint] {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let points = exhaustTempHistory.filter { $0.date >= sevenDaysAgo }
        return points.isEmpty ? exhaustTempHistory : points
    }
    
    public var exhaustPeakToday: Double {
        let pts = todayExhaustPoints
        guard !pts.isEmpty else { return 182.0 }
        return pts.map(\.temperature).max() ?? 182.0
    }
    
    public var exhaustOperatingAvg: Double {
        let active = todayExhaustPoints.filter { $0.temperature >= 60.0 }
        guard !active.isEmpty else { return 142.0 }
        return active.map(\.temperature).reduce(0.0, +) / Double(active.count)
    }
    
    // MARK: - Telemetry Recording
    
    public func recordTelemetry(roomTemp: Double, exhaustTemp: Double) {
        let now = Date()
        // Record at most once every 60 seconds to avoid bloating
        guard now.timeIntervalSince(lastRecordedDate) >= 60.0 else { return }
        lastRecordedDate = now
        
        if roomTemp > 5.0 && roomTemp < 45.0 {
            roomTempHistory.append(TemperaturePoint(date: now, temperature: roomTemp))
            trimHistory(&roomTempHistory)
        }
        
        if exhaustTemp >= 10.0 && exhaustTemp < 350.0 {
            exhaustTempHistory.append(TemperaturePoint(date: now, temperature: exhaustTemp))
            trimHistory(&exhaustTempHistory)
        }
        
        saveHistory()
    }
    
    private func trimHistory(_ history: inout [TemperaturePoint]) {
        let calendar = Calendar.current
        if let limitDate = calendar.date(byAdding: .day, value: -32, to: Date()) {
            history.removeAll { $0.date < limitDate }
        }
    }
    
    // MARK: - Persistence (Off-Main-Thread File Storage)
    
    private func saveHistory() {
        let roomSnapshot = self.roomTempHistory
        let exhaustSnapshot = self.exhaustTempHistory
        let roomURL = self.roomHistoryFileURL
        let exhaustURL = self.exhaustHistoryFileURL
        
        fileQueue.async {
            if let roomURL = roomURL, let data = try? JSONEncoder().encode(roomSnapshot) {
                try? FileManager.default.createDirectory(at: roomURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: roomURL, options: .atomic)
            }
            if let exhaustURL = exhaustURL, let data = try? JSONEncoder().encode(exhaustSnapshot) {
                try? FileManager.default.createDirectory(at: exhaustURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: exhaustURL, options: .atomic)
            }
        }
    }
    
    private func loadHistory() {
        // 1. Primär: Datei-basierter Cache
        if let url = roomHistoryFileURL, let data = try? Data(contentsOf: url),
           let points = try? JSONDecoder().decode([TemperaturePoint].self, from: data), !points.isEmpty {
            self.roomTempHistory = points
        } else if let roomData = UserDefaults.standard.data(forKey: roomHistoryKey),
                  let points = try? JSONDecoder().decode([TemperaturePoint].self, from: roomData), !points.isEmpty {
            // Migration von UserDefaults zur Entlastung von cfprefsd
            self.roomTempHistory = points
            UserDefaults.standard.removeObject(forKey: roomHistoryKey)
        }
        
        if let url = exhaustHistoryFileURL, let data = try? Data(contentsOf: url),
           let points = try? JSONDecoder().decode([TemperaturePoint].self, from: data), !points.isEmpty {
            self.exhaustTempHistory = points
        } else if let exhaustData = UserDefaults.standard.data(forKey: exhaustHistoryKey),
                  let points = try? JSONDecoder().decode([TemperaturePoint].self, from: exhaustData), !points.isEmpty {
            // Migration von UserDefaults zur Entlastung von cfprefsd
            self.exhaustTempHistory = points
            UserDefaults.standard.removeObject(forKey: exhaustHistoryKey)
        }
    }
    
    // MARK: - Synthetic Seed Data
    
    public func seedInitialDataIfNeeded(currentRoom: Double = 21.6, currentExhaust: Double = 135.0, targetRoom: Double = 22.0) {
        if roomTempHistory.count < 15 {
            seedRoomHistory(current: currentRoom, target: targetRoom)
        }
        if exhaustTempHistory.count < 15 {
            seedExhaustHistory(current: currentExhaust)
        }
    }
    
    private func seedRoomHistory(current: Double, target: Double) {
        var points: [TemperaturePoint] = []
        let calendar = Calendar.current
        let now = Date()
        let baseTarget = target > 15.0 ? target : 22.0
        
        // Generate hourly points for the past 30 days
        for dayOffset in (0...30).reversed() {
            guard let dayDate = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let dayStart = calendar.startOfDay(for: dayDate)
            
            // Generate realistic diurnal rhythm (night drop, morning heating, stable day, evening)
            for hour in stride(from: 0, to: 24, by: 2) {
                guard let pointDate = calendar.date(byAdding: .hour, value: hour, to: dayStart) else { continue }
                if pointDate > now { continue }
                
                let hourD = Double(hour)
                let tempVariation: Double
                if hourD >= 0 && hourD < 6 {
                    // Nachtabsenkung: 19.4°C - 20.2°C
                    tempVariation = -1.8 + sin(hourD * .pi / 6.0) * 0.4
                } else if hourD >= 6 && hourD < 9 {
                    // Morgenaufheizung
                    tempVariation = -1.0 + ((hourD - 6.0) / 3.0) * 1.5
                } else if hourD >= 9 && hourD < 22 {
                    // Behaglicher Tagesbetrieb: ~21.5°C - 22.4°C
                    tempVariation = 0.2 + sin((hourD - 9.0) * .pi / 13.0) * 0.4
                } else {
                    // Abkühlphase ab 22 Uhr
                    tempVariation = -0.5 - ((hourD - 22.0) / 2.0) * 0.8
                }
                
                let randomJitter = Double.random(in: -0.2...0.25)
                let simulatedTemp = min(24.0, max(18.5, baseTarget + tempVariation + randomJitter))
                points.append(TemperaturePoint(date: pointDate, temperature: (simulatedTemp * 10).rounded() / 10))
            }
        }
        
        // Append current actual reading as newest point
        points.append(TemperaturePoint(date: now, temperature: current > 5.0 ? current : baseTarget))
        self.roomTempHistory = points.sorted { $0.date < $1.date }
        saveHistory()
    }
    
    private func seedExhaustHistory(current: Double) {
        var points: [TemperaturePoint] = []
        let calendar = Calendar.current
        let now = Date()
        
        // Generate points for the past 7 days (heating cycles morning and evening)
        for dayOffset in (0...7).reversed() {
            guard let dayDate = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let dayStart = calendar.startOfDay(for: dayDate)
            
            for hour in stride(from: 0, to: 24, by: 1) {
                guard let pointDate = calendar.date(byAdding: .hour, value: hour, to: dayStart) else { continue }
                if pointDate > now { continue }
                
                let hourD = Double(hour)
                let exhaustTemp: Double
                
                // Morning burn: 06:00 to 10:00
                if hourD >= 6 && hourD <= 10 {
                    if hourD == 6 { exhaustTemp = 85.0 + Double.random(in: 0...15) } // Zündung
                    else if hourD == 7 { exhaustTemp = 165.0 + Double.random(in: -10...15) } // Peak
                    else { exhaustTemp = 145.0 + Double.random(in: -8...10) } // Modulation
                }
                // Evening burn: 17:00 to 22:00
                else if hourD >= 17 && hourD <= 22 {
                    if hourD == 17 { exhaustTemp = 92.0 + Double.random(in: 0...20) }
                    else if hourD == 18 { exhaustTemp = 175.0 + Double.random(in: -8...12) }
                    else { exhaustTemp = 150.0 + Double.random(in: -10...12) }
                }
                // Standby / Off
                else {
                    exhaustTemp = 26.0 + Double.random(in: -2...4)
                }
                
                points.append(TemperaturePoint(date: pointDate, temperature: exhaustTemp.rounded()))
            }
        }
        
        points.append(TemperaturePoint(date: now, temperature: current > 15.0 ? current : 138.0))
        self.exhaustTempHistory = points.sorted { $0.date < $1.date }
        saveHistory()
    }
}
