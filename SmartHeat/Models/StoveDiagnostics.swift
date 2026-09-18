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
    
    public init(
        totalOperatingHours: Int = 1842,
        heatingHours: Int = 1420,
        ignitionCount: Int = 487,
        serviceHoursLimit: Int = 2000,
        firmwareVersion: String = "TiEmme v01.03",
        boardCode: String = "D1000 - 25016460",
        recipeNumber: Int = 1
    ) {
        self.totalOperatingHours = totalOperatingHours
        self.heatingHours = heatingHours
        self.ignitionCount = ignitionCount
        self.serviceHoursLimit = serviceHoursLimit
        self.firmwareVersion = firmwareVersion
        self.boardCode = boardCode
        self.recipeNumber = recipeNumber
    }
    
    /// Hours remaining until annual / 2000h service inspection is due
    public var hoursUntilService: Int {
        guard totalOperatingHours > 0 else { return serviceHoursLimit }
        let remainder = totalOperatingHours % serviceHoursLimit
        return remainder == 0 ? 0 : (serviceHoursLimit - remainder)
    }
    
    /// Service inspection completion percentage (0.0 to 1.0)
    public var serviceProgress: Double {
        guard totalOperatingHours > 0 else { return 0.0 }
        let remainder = totalOperatingHours % serviceHoursLimit
        if remainder == 0 { return 1.0 }
        return min(1.0, max(0.0, Double(remainder) / Double(serviceHoursLimit)))
    }
    
    /// True if service is imminent (< 200 hours) or overdue
    public var isServiceImminent: Bool {
        hoursUntilService <= 200
    }
    
    /// True if 2000h service is overdue
    public var isServiceDue: Bool {
        hoursUntilService == 0
    }
}
