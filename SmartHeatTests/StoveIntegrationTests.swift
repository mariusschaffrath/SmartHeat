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
    
    func testPelletTankManagerInitializationAndRefill() {
        let manager = PelletTankManager()
        XCTAssertEqual(manager.tankCapacity, 20.0, "Dielle Ghibli Kombi 10 kW hat 20.0 kg Tankkapazität")
        XCTAssertEqual(manager.bagWeight, 15.0, "Standard-Sackgröße ist 15.0 kg")
        
        // Voll befüllen
        manager.refillFull()
        XCTAssertEqual(manager.currentLevel, 20.0)
        XCTAssertEqual(manager.fillPercentage, 100.0)
        XCTAssertFalse(manager.isLowPellet)
        
        // Fast leer setzen (4 kg = 20%)
        manager.setLevel(kg: 4.0)
        XCTAssertEqual(manager.currentLevel, 4.0)
        XCTAssertEqual(manager.fillPercentage, 20.0)
        XCTAssertTrue(manager.isLowPellet)
        
        // +1 Sack (15 kg) nachfüllen -> 4 + 15 = 19 kg
        manager.refillBag()
        XCTAssertEqual(manager.currentLevel, 19.0)
        XCTAssertEqual(manager.fillPercentage, 95.0)
        XCTAssertFalse(manager.isLowPellet)
        
        // Weiterer Sack wird bei 20.0 kg gekappt
        manager.refillBag()
        XCTAssertEqual(manager.currentLevel, 20.0)
    }
    
    func testPelletTankConsumptionAndWoodMode() {
        let manager = PelletTankManager()
        manager.setLevel(kg: 10.0)
        
        // Test P1 bis P5 Verbrauchsraten für Ghibli 10 kW
        manager.updateTracking(statusCode: 5, powerLevel: 1, isWood: false)
        XCTAssertEqual(manager.currentHourlyConsumption, 0.65, accuracy: 0.001, "P1 Teillast: 0.65 kg/h")
        XCTAssertEqual(manager.remainingHours, 10.0 / 0.65, accuracy: 0.1)
        
        manager.updateTracking(statusCode: 5, powerLevel: 5, isWood: false)
        XCTAssertEqual(manager.currentHourlyConsumption, 2.25, accuracy: 0.001, "P5 Volllast: 2.25 kg/h")
        XCTAssertEqual(manager.remainingHours, 10.0 / 2.25, accuracy: 0.1)
        
        // Scheitholzbetrieb aktiv -> Verbrauch muss auf 0 pausieren
        manager.updateTracking(statusCode: 13, powerLevel: 3, isWood: true)
        XCTAssertTrue(manager.isWoodModeActive)
        XCTAssertEqual(manager.currentHourlyConsumption, 0.0, "Holzverbrennung verbraucht 0.0 kg/h Pellets")
        
        // Zündungs-Primer Abzug (200g) beim Start von AUS -> Zündung
        manager.updateTracking(statusCode: 0, powerLevel: 1, isWood: false)
        let beforeIgnition = manager.currentLevel
        manager.updateTracking(statusCode: 2, powerLevel: 1, isWood: false)
        XCTAssertEqual(manager.currentLevel, beforeIgnition - 0.20, accuracy: 0.001, "Zündungs-Primer von 200g abgezogen")
    }
    
    func testTelemetryExtendedPowerAndWoodDecoding() {
        let liveDump = [
            "1000010000000007160300d704000000028801",
            "0c81013100010b060501000000b401",
            "12ffff0015000000000100000000000000",
            "12fff700d7000000000101000000000000",
            "0e016c00030001000600000001016c0007",
            "0e01ed00b4006401900001000101ed0000"
        ]
        
        let result = cloudService.parseAllTelemetry(liveDump)
        XCTAssertNotNil(result)
        if let (room, exhaust, target, status, powerLevel, isWood) = result {
            XCTAssertEqual(room, 21.5, accuracy: 0.01)
            XCTAssertEqual(exhaust, 21.0, accuracy: 0.01)
            XCTAssertEqual(target, 18.0, accuracy: 0.01)
            XCTAssertEqual(status, 0)
            XCTAssertEqual(powerLevel, 3, "0e016c mit 0003 setzt Power-Stufe auf 3")
            XCTAssertFalse(isWood)
        }
    }
}
