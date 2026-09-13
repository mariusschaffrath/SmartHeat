import XCTest
import Combine
@testable import SmartHeat

@MainActor
final class StoveIntegrationTests: XCTestCase {
    var cloudService: CloudService!

    override func setUp() {
        super.setUp()
        cloudService = CloudService()
    }

    func testAllValuesDecoding() {
        // Exakte Daten aus Marius' Screenshot
        let mockValues = [
            "10000100000b0007135400d804000000018801", // Main Values (Index 0)
            "0c81013000010b060501000000bd01",         // Info (Index 1)
            "12ffff0022000000000100000000000000",
            "12fff700d8000000000101000000000000",
            "12ffe20000000000000100000000000000",
            "12fffa0000000000000100000000000000",
            "0e016c00060001000600000001016c0007",
            "0e023f00000000000600000001023f0007",
            "12fffb0000000000000100000000000000",
            "0e016b00060001000600000001016b0007",
            "12fff60000000000000100000000000000",
            "12fffc0000000000000100000000000000",
            "0e01800258000102580000000101800000",      // Exhaust (Index 12)
            "0e017d00050000000600000001017d0000"       // Target (Index 13)
        ]
        
        let result = cloudService.parseAllValues(mockValues)
        
        XCTAssertNotNil(result, "Parser sollte ein Ergebnis liefern")
        
        if let (room, exhaust, target, status) = result {
            print("SIMULATION ERGEBNIS -> Raum: \(room)°, Abgas: \(exhaust)°, Ziel: \(target)°, Status: \(status)")
            
            // Verifizierung basierend auf der offiziellen Dielle SERVIZI2W Dekodierung
            XCTAssertEqual(room, 21.6, accuracy: 0.01, "Raumtemperatur sollte 21.6 sein (Index 0 Offset 20)")
            XCTAssertEqual(exhaust, 34.0, accuracy: 0.01, "Abgastemperatur sollte 34.0 sein (Index 2, 12ffff0022)")
            XCTAssertEqual(target, 18.9, accuracy: 0.01, "Solltemperatur sollte 18.9 sein (Index 1, 0c81 termostato 00bd)")
            XCTAssertEqual(status, 11, "Status sollte 11 (0x0B = Standby) sein basierend auf Index 0 Offset 10")
        }
    }
    
    func testCommandFormatting() {
        XCTAssertEqual(StoveCommand.turnOn.rawString, "05040000")
        XCTAssertEqual(StoveCommand.turnOff.rawString, "05050000")
        XCTAssertEqual(StoveCommand.poll2Ways.rawString, "2WL0")
        
        // Target temp 18.5°C = 185 = 0x00b9
        let tempCmd = StoveCommand.writeParameter(id: "01ed", value: 185)
        XCTAssertEqual(tempCmd.rawString, "050e01ed00b9")
    }
    
    func testRealStoveLiveDumpDecoding() {
        // Echte Live-Daten von Ofen 192.168.178.188 (25 Blöcke)
        let liveDump = [
            "1000010000000007160300d704000000028801",
            "0c81013100010b060501000000b401",
            "12ffff0015000000000100000000000000",
            "12fff700d7000000000101000000000000",
            "12ffe20000000000000100000000000000",
            "12fffa0000000000000100000000000000",
            "0e016c00060001000600000001016c0007",
            "0e023f00020000000600000001023f0007",
            "12fffb0000000000000100000000000000",
            "0e016b00060001000600000001016b0007",
            "12fff60000000000000100000000000000",
            "12fffc0000000000000100000000000000",
            "0e01800258000102580000000101800000",
            "0e017d00050000000600000001017d0000",
            "12ffdf0000000000000100000000000000",
            "12ffde0000000000000100000000000000",
            "12ffd30000000000000100000000000000",
            "12ffd80000000000000100000000000000",
            "0e02660001000000060000000102660007",
            "0e027e00010000000600000001027e0007",
            "12ffe00000000000000101000000000000",
            "12ffe80000000000000101000000000000",
            "0e01ed00b4006401900001000101ed0000",
            "12006900b4006401900001000100000000"
        ]
        
        let result = cloudService.parseAllValues(liveDump)
        XCTAssertNotNil(result)
        if let (room, exhaust, target, status) = result {
            XCTAssertEqual(room, 21.5, accuracy: 0.01, "Raumtemperatur sollte 21.5°C sein")
            XCTAssertEqual(exhaust, 21.0, accuracy: 0.01, "Abgastemperatur sollte 21.0°C sein")
            XCTAssertEqual(target, 18.0, accuracy: 0.01, "Solltemperatur sollte 18.0°C sein")
            XCTAssertEqual(status, 0, "Status sollte 0 (AUS) sein")
        }
    }
}
