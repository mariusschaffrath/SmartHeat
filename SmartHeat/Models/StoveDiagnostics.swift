//
//  StoveDiagnostics.swift
//  SmartHeat
//
//  Motherboard hardware diagnostics & maintenance tracking data model.
//

import Foundation

public struct StoveDiagnostics: Codable, Equatable {
    public var totalOperatingHours: Int
    public var heatingHours: Int
    public var ignitionCount: Int
    public var serviceHoursLimit: Int
    public var firmwareVersion: String
    public var boardCode: String
    public var recipeNumber: Int
    public var totalOperatingSeconds: Double
    public var heatingSeconds: Double
    public var lastServiceOperatingHours: Int
    public var lastServiceDate: Date?
    
    public init(
        totalOperatingHours: Int = 1842,
        heatingHours: Int = 1420,
        ignitionCount: Int = 487,
        serviceHoursLimit: Int = 2000,
        firmwareVersion: String = "TiEmme v01.03",
        boardCode: String = "D1000 - 25016460",
        recipeNumber: Int = 1,
        totalOperatingSeconds: Double? = nil,
        heatingSeconds: Double? = nil,
        lastServiceOperatingHours: Int = 0,
        lastServiceDate: Date? = nil
    ) {
        self.totalOperatingHours = totalOperatingHours
        self.heatingHours = heatingHours
        self.ignitionCount = ignitionCount
        self.serviceHoursLimit = serviceHoursLimit
        self.firmwareVersion = firmwareVersion
        self.boardCode = boardCode
        self.recipeNumber = recipeNumber
        self.totalOperatingSeconds = totalOperatingSeconds ?? Double(totalOperatingHours * 3600)
        self.heatingSeconds = heatingSeconds ?? Double(heatingHours * 3600)
        self.lastServiceOperatingHours = lastServiceOperatingHours
        self.lastServiceDate = lastServiceDate
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let total = try container.decodeIfPresent(Int.self, forKey: .totalOperatingHours) ?? 1842
        let heating = try container.decodeIfPresent(Int.self, forKey: .heatingHours) ?? 1420
        self.totalOperatingHours = total
        self.heatingHours = heating
        self.ignitionCount = try container.decodeIfPresent(Int.self, forKey: .ignitionCount) ?? 487
        self.serviceHoursLimit = try container.decodeIfPresent(Int.self, forKey: .serviceHoursLimit) ?? 2000
        self.firmwareVersion = try container.decodeIfPresent(String.self, forKey: .firmwareVersion) ?? "TiEmme v01.03"
        self.boardCode = try container.decodeIfPresent(String.self, forKey: .boardCode) ?? "D1000 - 25016460"
        self.recipeNumber = try container.decodeIfPresent(Int.self, forKey: .recipeNumber) ?? 1
        self.totalOperatingSeconds = try container.decodeIfPresent(Double.self, forKey: .totalOperatingSeconds) ?? Double(total * 3600)
        self.heatingSeconds = try container.decodeIfPresent(Double.self, forKey: .heatingSeconds) ?? Double(heating * 3600)
        self.lastServiceOperatingHours = try container.decodeIfPresent(Int.self, forKey: .lastServiceOperatingHours) ?? 0
        self.lastServiceDate = try container.decodeIfPresent(Date.self, forKey: .lastServiceDate)
    }
    
    /// Laufende Betriebsstunden seit der letzten durchgeführten Wartung
    public var hoursSinceLastService: Int {
        max(0, totalOperatingHours - lastServiceOperatingHours)
    }
    
    /// Verbleibende Stunden bis zur nächsten 2.000h Inspektion
    public var hoursUntilService: Int {
        guard serviceHoursLimit > 0 else { return 0 }
        let remainder = hoursSinceLastService % serviceHoursLimit
        if hoursSinceLastService > 0 && remainder == 0 {
            return 0
        }
        return serviceHoursLimit - remainder
    }
    
    /// Service-Inspektions-Fortschritt (0.0 bis 1.0)
    public var serviceProgress: Double {
        guard serviceHoursLimit > 0 else { return 0.0 }
        let remainder = hoursSinceLastService % serviceHoursLimit
        if hoursSinceLastService > 0 && remainder == 0 {
            return 1.0
        }
        return min(1.0, max(0.0, Double(remainder) / Double(serviceHoursLimit)))
    }
    
    /// True if service is imminent (<= 200 hours) or overdue
    public var isServiceImminent: Bool {
        hoursUntilService <= 200
    }
    
    /// True if 2000h service is overdue
    public var isServiceDue: Bool {
        hoursUntilService == 0
    }
    
    /// Setzt das Wartungsintervall zurück und startet den 2.000h Zyklus ab den aktuellen Betriebsstunden neu
    public mutating func resetService(operatingHours: Int? = nil) {
        self.lastServiceOperatingHours = operatingHours ?? self.totalOperatingHours
        self.lastServiceDate = Date()
    }
}
