//
//  HardwareChrono.swift
//  SmartHeat
//
//  Direct hardware timetable data model for Dielle / TiEmme motherboard EEPROM.
//  Corresponds to ["CCG","0"] (read) and ["CCS","71",...] (write) commands.
//

import Foundation

/// Represents a single time slot on the stove's motherboard (up to 3 per day).
public struct HardwareChronoSlot: Codable, Identifiable, Equatable {
    public var id: Int // 1, 2, or 3
    public var startTime: String // "HH:mm", e.g. "06:00"
    public var endTime: String   // "HH:mm", e.g. "08:30"
    public var isEnabled: Bool   // Slot active flag
    
    public init(id: Int, startTime: String = "00:00", endTime: String = "00:00", isEnabled: Bool = false) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.isEnabled = isEnabled
    }
    
    /// Returns start time as Date components (hour, minute)
    public var startHourAndMinute: (hour: Int, minute: Int) {
        let parts = startTime.split(separator: ":").compactMap { Int($0) }
        return (parts.first ?? 0, parts.count > 1 ? parts[1] : 0)
    }
    
    /// Returns end time as Date components (hour, minute)
    public var endHourAndMinute: (hour: Int, minute: Int) {
        let parts = endTime.split(separator: ":").compactMap { Int($0) }
        return (parts.first ?? 0, parts.count > 1 ? parts[1] : 0)
    }
}

/// Represents one day of the week (1=Monday to 7=Sunday) containing 3 hardware slots.
public struct HardwareChronoDay: Codable, Identifiable, Equatable {
    public var id: Int // 1=Mo, 2=Di, 3=Mi, 4=Do, 5=Fr, 6=Sa, 7=So
    public var name: String
    public var shortName: String
    public var slots: [HardwareChronoSlot]
    
    public init(id: Int, name: String, shortName: String, slots: [HardwareChronoSlot]) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.slots = slots
    }
    
    public static func defaultDays() -> [HardwareChronoDay] {
        let dayNames = [
            (1, "Montag", "Mo"),
            (2, "Dienstag", "Di"),
            (3, "Mittwoch", "Mi"),
            (4, "Donnerstag", "Do"),
            (5, "Freitag", "Fr"),
            (6, "Samstag", "Sa"),
            (7, "Sonntag", "So")
        ]
        return dayNames.map { id, name, short in
            HardwareChronoDay(
                id: id,
                name: name,
                shortName: short,
                slots: [
                    HardwareChronoSlot(id: 1, startTime: "06:00", endTime: "08:30", isEnabled: false),
                    HardwareChronoSlot(id: 2, startTime: "16:30", endTime: "21:30", isEnabled: false),
                    HardwareChronoSlot(id: 3, startTime: "00:00", endTime: "00:00", isEnabled: false)
                ]
            )
        }
    }
}

/// Chrono operation modes supported by TiEmme hardware
public enum HardwareChronoMode: Int, Codable, CaseIterable, Identifiable {
    case off = 0
    case daily = 1      // Giorno (jeder Tag individuell)
    case weekly = 2     // Settimanale (Mo-So gleicher Plan)
    case weekend = 3    // Week-end (Werktage Mo-Fr vs Wochenende Sa-So)
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .off: return "Deaktiviert"
        case .daily: return "Tagesprogramm (Individuell)"
        case .weekly: return "Wochenprogramm (Mo–So gleich)"
        case .weekend: return "Werktags / Wochenende"
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .off: return "Aus"
        case .daily: return "Täglich"
        case .weekly: return "Woche"
        case .weekend: return "Wochenende"
        }
    }
}

/// Full timetable plan stored on the stove's motherboard
public struct HardwareChronoPlan: Codable, Equatable {
    public var mode: HardwareChronoMode
    public var isGloballyEnabled: Bool
    public var days: [HardwareChronoDay]
    
    public init(
        mode: HardwareChronoMode = .daily,
        isGloballyEnabled: Bool = false,
        days: [HardwareChronoDay] = HardwareChronoDay.defaultDays()
    ) {
        self.mode = mode
        self.isGloballyEnabled = isGloballyEnabled
        self.days = days
    }
    
    // MARK: - Parser for ["CCG", "71", "<mode>", "1", ...]
    public static func parseFromResponse(_ responseArray: [String]) -> HardwareChronoPlan? {
        guard responseArray.count >= 73, responseArray[0] == "CCG" else {
            return nil
        }
        
        let modeInt = Int(responseArray[2]) ?? 0
        let mode = HardwareChronoMode(rawValue: modeInt) ?? .daily
        
        var parsedDays: [HardwareChronoDay] = []
        var ptr = 3 // starts at day index "1"
        
        let dayNames = [
            (1, "Montag", "Mo"),
            (2, "Dienstag", "Di"),
            (3, "Mittwoch", "Mi"),
            (4, "Donnerstag", "Do"),
            (5, "Freitag", "Fr"),
            (6, "Samstag", "Sa"),
            (7, "Sonntag", "So")
        ]
        
        for (dayId, name, short) in dayNames {
            guard ptr < responseArray.count else { break }
            // Day identifier e.g. "1"
            _ = responseArray[ptr]
            ptr += 1
            
            var slots: [HardwareChronoSlot] = []
            for slotId in 1...3 {
                guard ptr + 2 < responseArray.count else { break }
                let start = responseArray[ptr]
                let end = responseArray[ptr + 1]
                let flag = responseArray[ptr + 2]
                let isEnabled = (flag == "1" || flag == "true")
                slots.append(HardwareChronoSlot(id: slotId, startTime: start, endTime: end, isEnabled: isEnabled))
                ptr += 3
            }
            parsedDays.append(HardwareChronoDay(id: dayId, name: name, shortName: short, slots: slots))
        }
        
        return HardwareChronoPlan(
            mode: mode,
            isGloballyEnabled: mode != .off,
            days: parsedDays.count == 7 ? parsedDays : HardwareChronoDay.defaultDays()
        )
    }
    
    // MARK: - Serializer for ["CCS", "71", "<mode>", "1", ...]
    public func toCCSCommandString() -> String {
        var elements: [String] = ["\"CCS\"", "\"71\"", "\"\(mode.rawValue)\""]
        
        // Exakt 7 Tage (1..7) mit jeweils exakt 3 Slots (notfalls mit 00:00 aufgefüllt),
        // damit exakt 71 Parameter für das TiEmme-EEPROM übertragen werden.
        for dayId in 1...7 {
            elements.append("\"\(dayId)\"")
            let day = days.first(where: { $0.id == dayId })
            let daySlots = day?.slots ?? []
            
            for slotIndex in 0..<3 {
                if slotIndex < daySlots.count {
                    let slot = daySlots[slotIndex]
                    let start = slot.startTime.isEmpty ? "00:00" : slot.startTime
                    let end = slot.endTime.isEmpty ? "00:00" : slot.endTime
                    elements.append("\"\(start)\"")
                    elements.append("\"\(end)\"")
                    elements.append("\"\(slot.isEnabled ? "1" : "0")\"")
                } else {
                    // Fehlende Slots mit 00:00 auffüllen
                    elements.append("\"00:00\"")
                    elements.append("\"00:00\"")
                    elements.append("\"0\"")
                }
            }
        }
        
        return "[\(elements.joined(separator: ","))]\n"
    }
}
