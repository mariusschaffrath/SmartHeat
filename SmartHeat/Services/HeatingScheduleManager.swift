//
//  HeatingScheduleManager.swift
//  SmartHeat
//
//  Manages weekly heating schedules, time slots, temperature presets,
//  and automatic timetable transitions.
//

import Foundation
import SwiftUI
import Combine

public struct HeatingTimeSlot: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    public var targetTemp: Double
    public var isEnabled: Bool
    
    public init(
        id: UUID = UUID(),
        name: String,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        targetTemp: Double,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.targetTemp = targetTemp
        self.isEnabled = isEnabled
    }
    
    public var timeRangeString: String {
        String(format: "%02d:%02d – %02d:%02d", startHour, startMinute, endHour, endMinute)
    }
    
    public func contains(currentHour: Int, currentMinute: Int) -> Bool {
        let currentMinutes = currentHour * 60 + currentMinute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute
        
        if endMinutes > startMinutes {
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            // Over midnight slot
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }
}

public struct DaySchedule: Identifiable, Codable, Equatable {
    public let id: Int // 1 = Monday, 7 = Sunday
    public var name: String
    public var shortName: String
    public var isEnabled: Bool
    public var slots: [HeatingTimeSlot]
    
    public init(id: Int, name: String, shortName: String, isEnabled: Bool = true, slots: [HeatingTimeSlot] = []) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.isEnabled = isEnabled
        self.slots = slots
    }
}

@MainActor
public class HeatingScheduleManager: ObservableObject {
    public static let shared = HeatingScheduleManager()
    
    private let storageKey = "smartheat_heating_schedule_v2"
    private let activeKey = "smartheat_heating_schedule_active"
    private let defaultNightTempKey = "smartheat_night_base_temp"
    
    @Published public var isScheduleActive: Bool {
        didSet { UserDefaults.standard.set(isScheduleActive, forKey: activeKey) }
    }
    @Published public var defaultNightTemp: Double {
        didSet { UserDefaults.standard.set(defaultNightTemp, forKey: defaultNightTempKey) }
    }
    @Published public var weeklySchedule: [DaySchedule] = []
    
    @Published public var overrideTargetTemp: Double? = nil
    @Published public var overrideUntil: Date? = nil
    
    public init() {
        self.isScheduleActive = UserDefaults.standard.bool(forKey: activeKey)
        self.defaultNightTemp = UserDefaults.standard.object(forKey: defaultNightTempKey) as? Double ?? 19.0
        loadSchedule()
        if weeklySchedule.isEmpty {
            applyComfortPreset()
        }
    }
    
    nonisolated deinit {}
    
    // MARK: - Active Scheduled Temperature Calculation
    public func getCurrentTargetTemperature() -> Double? {
        guard isScheduleActive else { return nil }
        
        // 1. Check temporary boost/override
        if let overrideTemp = overrideTargetTemp, let until = overrideUntil {
            if Date() < until {
                return overrideTemp
            } else {
                overrideTargetTemp = nil
                overrideUntil = nil
            }
        }
        
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        // Convert Sunday=1..Saturday=7 to Monday=1..Sunday=7
        let dayIndex = (weekday == 1) ? 7 : (weekday - 1)
        
        guard let daySchedule = weeklySchedule.first(where: { $0.id == dayIndex }), daySchedule.isEnabled else {
            return defaultNightTemp
        }
        
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        
        for slot in daySchedule.slots where slot.isEnabled {
            if slot.contains(currentHour: currentHour, currentMinute: currentMinute) {
                return slot.targetTemp
            }
        }
        
        return defaultNightTemp
    }
    
    // MARK: - Quick Overrides
    public func activateBoost(temp: Double = 23.0, durationHours: Double = 2.0) {
        self.overrideTargetTemp = temp
        self.overrideUntil = Date().addingTimeInterval(durationHours * 3600)
    }
    
    public func cancelOverride() {
        self.overrideTargetTemp = nil
        self.overrideUntil = nil
    }
    
    // MARK: - Presets
    public func applyComfortPreset() {
        var days: [DaySchedule] = []
        let dayNames = [
            (1, "Montag", "Mo"),
            (2, "Dienstag", "Di"),
            (3, "Mittwoch", "Mi"),
            (4, "Donnerstag", "Do"),
            (5, "Freitag", "Fr"),
            (6, "Samstag", "Sa"),
            (7, "Sonntag", "So")
        ]
        
        for (id, name, short) in dayNames {
            let isWeekend = (id >= 6)
            var slots: [HeatingTimeSlot] = []
            
            if !isWeekend {
                // Werktage: Morgens 06:00 - 08:30 (22°C) & Nachmittags/Abends 16:30 - 22:30 (22°C)
                slots.append(HeatingTimeSlot(name: "Morgenaufheizung", startHour: 6, startMinute: 0, endHour: 8, endMinute: 30, targetTemp: 22.0))
                slots.append(HeatingTimeSlot(name: "Abend-Komfort", startHour: 16, startMinute: 30, endHour: 22, endMinute: 30, targetTemp: 22.0))
            } else {
                // Wochenende: Gemütlich 07:30 - 23:00 durchgehend 22°C
                slots.append(HeatingTimeSlot(name: "Wochenend-Komfort", startHour: 7, startMinute: 30, endHour: 23, endMinute: 0, targetTemp: 22.0))
            }
            
            days.append(DaySchedule(id: id, name: name, shortName: short, isEnabled: true, slots: slots))
        }
        
        self.weeklySchedule = days
        saveSchedule()
    }
    
    public func applyEcoPreset() {
        var days: [DaySchedule] = []
        let dayNames = [
            (1, "Montag", "Mo"),
            (2, "Dienstag", "Di"),
            (3, "Mittwoch", "Mi"),
            (4, "Donnerstag", "Do"),
            (5, "Freitag", "Fr"),
            (6, "Samstag", "Sa"),
            (7, "Sonntag", "So")
        ]
        
        for (id, name, short) in dayNames {
            let slots = [
                HeatingTimeSlot(name: "Feierabend-Heizen", startHour: 17, startMinute: 30, endHour: 21, endMinute: 30, targetTemp: 20.5)
            ]
            days.append(DaySchedule(id: id, name: name, shortName: short, isEnabled: true, slots: slots))
        }
        
        self.defaultNightTemp = 18.0
        self.weeklySchedule = days
        saveSchedule()
    }
    
    public func saveSchedule() {
        if let data = try? JSONEncoder().encode(weeklySchedule) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadSchedule() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let loaded = try? JSONDecoder().decode([DaySchedule].self, from: data) {
            self.weeklySchedule = loaded
        }
    }
}
