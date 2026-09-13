import Foundation

/// Represents a Dielle 4HEAT 2ways protocol command
public struct StoveCommand: Codable, Equatable {
    public let rawString: String
    
    public init(rawString: String) {
        self.rawString = rawString
    }
    
    // Core Commands (Power) - Exact 2ways Dielle FileMap specification for device 25016460
    public static let turnOn = StoveCommand(rawString: "05040000")
    public static let turnOff = StoveCommand(rawString: "05050000")
    public static let unlock = StoveCommand(rawString: "05050000")
    
    // Read / Polling Commands
    public static let poll2Ways = StoveCommand(rawString: "2WL0")
    public static let pollSyevo = StoveCommand(rawString: "SEL0")
    public static let selAll = StoveCommand(rawString: "2WL0")
    
    // Read Registers (Status & Temps - Syevo fallback)
    public static let readStatus = StoveCommand(rawString: "I30001000000000000")
    public static let readRoomTemp = StoveCommand(rawString: "I30006000000000000")
    public static let readWaterTemp = StoveCommand(rawString: "I30017000000000000")
    public static let readExhaustTemp = StoveCommand(rawString: "I30005000000000000")
    public static let readThermostat = StoveCommand(rawString: "A20493000000000000")
    
    // Syevo Legacy Power Commands
    public static let turnOnSyevo = StoveCommand(rawString: "J30253000000000001")
    public static let turnOffSyevo = StoveCommand(rawString: "J30254000000000001")
    public static let unlockSyevo = StoveCommand(rawString: "J30255000000000001")
    
    /// Create a WRITE parameter command for 2ways Dielle (050e + 4-digit param ID + 4-digit hex value)
    /// e.g. target temp: id "01ed", value 215 (21.5°C) -> "050e01ed00d7"
    public static func writeParameter(id: String = "01ed", value: Int) -> StoveCommand {
        let hexVal = String(format: "%04x", value)
        return StoveCommand(rawString: "050e\(id)\(hexVal)")
    }
    
    /// Create a WRITE parameter command for Syevo (B + 5-digit id + 12-digit value)
    public static func writeParameterSyevo(id: String, value: Int) -> StoveCommand {
        let valStr = String(format: "%012d", value)
        return StoveCommand(rawString: "B\(id)\(valStr)")
    }
}
