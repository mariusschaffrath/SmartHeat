import Foundation

/// Represents a 4HEAT protocol command (18 characters)
struct StoveCommand: Codable, Equatable {
    let rawString: String
    
    init(rawString: String) {
        if rawString == "SEL0" {
            self.rawString = rawString
        } else if rawString.count < 18 {
            let padding = String(repeating: "0", count: 18 - rawString.count)
            self.rawString = rawString + padding
        } else {
            self.rawString = String(rawString.prefix(18))
        }
    }
    
    // Core Commands (Power)
    // Home Assistant uses J30253... for ON, J30254... for OFF
    static let turnOn = StoveCommand(rawString: "J30253000000000001")
    static let turnOff = StoveCommand(rawString: "J30254000000000001")
    static let unlock = StoveCommand(rawString: "J30255000000000001")
    
    // Read Registers (Status & Temps)
    static let readStatus = StoveCommand(rawString: "I30001000000000000")
    static let readRoomTemp = StoveCommand(rawString: "I30006000000000000")
    static let readWaterTemp = StoveCommand(rawString: "I30017000000000000")
    static let readExhaustTemp = StoveCommand(rawString: "I30005000000000000")
    static let readThermostat = StoveCommand(rawString: "A20493000000000000")
    
    static let selAll = StoveCommand(rawString: "SEL0")
    
    /// Create a WRITE parameter command (B prefix)
    static func writeParameter(id: String, value: Int) -> StoveCommand {
        // Value must be 12 digits padded with zeros
        let valueString = String(format: "%012d", value)
        // Command is B + 5-digit ID + 12-digit value = 18 chars
        return StoveCommand(rawString: "B\(id)\(valueString)")
    }
}
