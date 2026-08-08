import Foundation

/// Represents a Dielle 4HEAT 2ways protocol command
struct StoveCommand: Codable, Equatable {
    let rawString: String
    
    init(rawString: String) {
        self.rawString = rawString
    }
    
    // Core Commands (Power) - Exact 2ways Dielle FileMap specification for device 25016460
    static let turnOn = StoveCommand(rawString: "05040000")
    static let turnOff = StoveCommand(rawString: "05050000")
    static let unlock = StoveCommand(rawString: "05050000")
    
    // Read Registers (Status & Temps)
    static let readStatus = StoveCommand(rawString: "I30001000000000000")
    static let readRoomTemp = StoveCommand(rawString: "I30006000000000000")
    static let readWaterTemp = StoveCommand(rawString: "I30017000000000000")
    static let readExhaustTemp = StoveCommand(rawString: "I30005000000000000")
    static let readThermostat = StoveCommand(rawString: "A20493000000000000")
    
    static let selAll = StoveCommand(rawString: "SEL0")
    
    /// Create a WRITE parameter command for 2ways Dielle (050e01ed + 4-digit hex)
    static func writeParameter(id: String, value: Int) -> StoveCommand {
        let hexVal = String(format: "%04x", value)
        return StoveCommand(rawString: "050e01ed\(hexVal)")
    }
}
