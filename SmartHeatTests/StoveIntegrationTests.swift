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
            
            // Verifizierung basierend auf dem neuen Deep-Parsing
            XCTAssertEqual(room, 21.6, "Raumtemperatur sollte 21.6 sein (Index 0, Offset 20)")
            XCTAssertEqual(exhaust, 0.7, "Abgastemperatur sollte 0.7 sein (Index 0, Offset 6 - Ofen ist wohl gerade aus)")
            XCTAssertEqual(status, 11, "Status sollte 11 (0x0B) sein basierend auf Index 0 Offset 10")
        }
    }
}
