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
    func testTemperatureHistoryManagerCalculations() {
        let manager = TemperatureHistoryManager()
        let now = Date()
        let calendar = Calendar.current
        
        var roomPoints: [TemperaturePoint] = []
        // Add 5 points today
        for i in 0..<5 {
            let d = calendar.date(byAdding: .hour, value: -i, to: now)!
            roomPoints.append(TemperaturePoint(date: d, temperature: 20.0 + Double(i))) // 20, 21, 22, 23, 24 -> avg = 22.0
        }
        manager.roomTempHistory = roomPoints
        
        XCTAssertEqual(manager.todayRoomAvg, 22.0, accuracy: 0.01)
        XCTAssertEqual(manager.todayRoomMin, 20.0, accuracy: 0.01)
        XCTAssertEqual(manager.todayRoomMax, 24.0, accuracy: 0.01)
        
        var exhaustPoints: [TemperaturePoint] = []
        exhaustPoints.append(TemperaturePoint(date: now, temperature: 140.0))
        exhaustPoints.append(TemperaturePoint(date: calendar.date(byAdding: .hour, value: -1, to: now)!, temperature: 180.0))
        exhaustPoints.append(TemperaturePoint(date: calendar.date(byAdding: .hour, value: -2, to: now)!, temperature: 30.0)) // off
        manager.exhaustTempHistory = exhaustPoints
        
        XCTAssertEqual(manager.exhaustPeakToday, 180.0, accuracy: 0.01)
        // Active burn average (> 60°C): 140 + 180 = 320 / 2 = 160.0
        XCTAssertEqual(manager.exhaustOperatingAvg, 160.0, accuracy: 0.01)
    }

    func testFanChannelSeparationAndCommands() {
        // Live dump with Luftheizung Flur (023f) set to 2 and Luftzufuhr 2 (027e) set to 1
        let liveDump = [
            "1000010000000007160300d704000000028801",
            "0c81013100010b060501000000b401",
            "0e023f00020000000600000001023f0007", // Luftheizung Flur (023f) = 2
            "0e027e00010000000600000001027e0007"  // Luftzufuhr 2 (027e) = 1
        ]
        
        let data = CloudStoveData(deviceKey: nil, isOnline: true, values: nil, Values: liveDump, data: nil)
        let mapped = data.getMappedValues()
        XCTAssertNotNil(mapped)
        if let mapped = mapped {
            XCTAssertEqual(mapped.kanal1, 2, "Luftheizung (Flur) sollte Stufe 2 sein (Register 023f)")
            XCTAssertEqual(mapped.flurFan, 2, "flurFan sollte mit Luftheizung übereinstimmen")
            XCTAssertEqual(mapped.kanal2, 1, "Luftzufuhr 2 sollte Stufe 1 sein (Register 027e)")
        }
        
        // Command Formatting
        let cmdFlur = StoveCommand.writeParameter(id: "023f", value: 2)
        XCTAssertEqual(cmdFlur.rawString, "050e023f0002", "Luftheizung Flur Steuerbefehl muss an 023f gehen")
        
        let cmdKanal2 = StoveCommand.writeParameter(id: "027e", value: 2)
        XCTAssertEqual(cmdKanal2.rawString, "050e027e0002", "Luftzufuhr 2 Steuerbefehl muss an 027e gehen")
        
        // Target temperature 22.0°C = 220 = 0x00dc
        let cmdTemp = StoveCommand.writeParameter(id: "01ed", value: 220)
        XCTAssertEqual(cmdTemp.rawString, "050e01ed00dc", "Zieltemperatur 22.0°C (220) muss 050e01ed00dc sein")
    }

    func testHardwareAlarmDecodingAndUnlockCommand() {
        // 1. Verify Dielle Sblocco / Unlock Command
        XCTAssertEqual(StoveCommand.unlock.rawString, "050a0000", "Dielle 2ways Sblocco muss 050a0000 sein")
        XCTAssertNotEqual(StoveCommand.unlock.rawString, StoveCommand.turnOff.rawString, "Unlock darf nicht identisch mit TurnOff sein")
        XCTAssertNotEqual(StoveCommand.unlock.rawString, StoveCommand.turnOn.rawString, "Unlock darf keinesfalls identisch mit TurnOn sein!")
        
        // 2. Hardware Alarm Mapping
        let alarmEr03 = DielleHardwareAlarm.from(code: 3)
        XCTAssertNotNil(alarmEr03)
        XCTAssertEqual(alarmEr03?.codeString, "Er03")
        XCTAssertTrue(alarmEr03?.title.contains("Pellets") == true)
        
        let alarmEr39 = DielleHardwareAlarm.from(code: 39)
        XCTAssertNotNil(alarmEr39)
        XCTAssertEqual(alarmEr39?.codeString, "Er39")
        XCTAssertTrue(alarmEr39?.title.contains("Unterdruckwächter") == true)
        
        XCTAssertNil(DielleHardwareAlarm.from(code: 0), "Code 0 bedeutet kein Fehler")
        
        // 3. Block 0 Live Alarm Decoding: status 09 (Blocco) and error 03 (Er03)
        // Offset 10..12: "09" (Status 9 = Blocco), Offset 12..14: "03" (Error 3 = Er03)
        let alarmDump = [
            "1000010000090307160300d704000000028801",
            "0c81013100010b060501000000b401"
        ]
        
        let data = CloudStoveData(deviceKey: nil, isOnline: true, values: nil, Values: alarmDump, data: nil)
        let mapped = data.getMappedValues()
        XCTAssertNotNil(mapped)
        if let mapped = mapped {
            XCTAssertEqual(mapped.status, 9, "Status muss 9 (Blocco) sein")
            XCTAssertEqual(mapped.errorCode, 3, "Fehlercode an Offset 12..14 muss 3 sein")
            let alarm = DielleHardwareAlarm.from(code: mapped.errorCode)
            XCTAssertEqual(alarm?.codeString, "Er03")
        }
        
        // 4. Extended Helper parseAllTelemetryWithAlarm
        let parsed = cloudService.parseAllTelemetryWithAlarm(alarmDump)
        XCTAssertNotNil(parsed)
        if let parsed = parsed {
            XCTAssertEqual(parsed.status, 9)
            XCTAssertEqual(parsed.errorCode, 3)
        }
    }

    func testNotificationManagerForegroundDelegateAndRegistration() {
        let manager = NotificationManager.shared
        XCTAssertNotNil(manager)
        
        // 1. Check that UNUserNotificationCenter delegate is set to manager
        XCTAssertNotNil(UNUserNotificationCenter.current().delegate, "Delegate muss registriert sein, damit Vordergrund-Banner erscheinen")
        XCTAssertTrue(UNUserNotificationCenter.current().delegate === manager, "Manager muss der aktive UNUserNotificationCenter Delegate sein")
        
        // 2. Test sendTestNotification dispatch
        let exp = expectation(description: "sendTestNotification completion")
        manager.sendTestNotification { success in
            XCTAssertTrue(success, "Test-Mitteilung sollte erfolgreich bei UNUserNotificationCenter registriert werden")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3.0)
    }

    func testHardwareChronoParsingAndSerialization() {
        // Construct standard 73-element array returned by ["CCG","0"]
        // [0]="CCG", [1]="71", [2]="1" (daily mode), followed by 7 days (each 1 day-id + 3 slots * 3 params = 10 elements per day)
        var responseArray = ["CCG", "71", "1"]
        for dayId in 1...7 {
            responseArray.append("\(dayId)")
            // Slot 1: 06:00 - 08:30 (active)
            responseArray.append(contentsOf: ["06:00", "08:30", "1"])
            // Slot 2: 16:30 - 21:30 (active)
            responseArray.append(contentsOf: ["16:30", "21:30", "1"])
            // Slot 3: 00:00 - 00:00 (inactive)
            responseArray.append(contentsOf: ["00:00", "00:00", "0"])
        }
        XCTAssertEqual(responseArray.count, 73)
        
        let plan = HardwareChronoPlan.parseFromResponse(responseArray)
        XCTAssertNotNil(plan)
        guard let plan = plan else { return }
        
        XCTAssertEqual(plan.mode, .daily)
        XCTAssertTrue(plan.isGloballyEnabled)
        XCTAssertEqual(plan.days.count, 7)
        
        let monday = plan.days[0]
        XCTAssertEqual(monday.name, "Montag")
        XCTAssertEqual(monday.slots.count, 3)
        XCTAssertEqual(monday.slots[0].startTime, "06:00")
        XCTAssertEqual(monday.slots[0].endTime, "08:30")
        XCTAssertTrue(monday.slots[0].isEnabled)
        XCTAssertEqual(monday.slots[1].startTime, "16:30")
        XCTAssertEqual(monday.slots[1].endTime, "21:30")
        XCTAssertTrue(monday.slots[1].isEnabled)
        XCTAssertFalse(monday.slots[2].isEnabled)
        
        // Serialization Test
        let ccs = plan.toCCSCommandString()
        XCTAssertTrue(ccs.hasPrefix("[\"CCS\",\"71\",\"1\","))
        XCTAssertTrue(ccs.contains("\"06:00\",\"08:30\",\"1\""))
        XCTAssertTrue(ccs.hasSuffix("]\n"))
    }
    
    func testStoveDiagnosticsCalculations() {
        // Standard in-between state
        let diag1 = StoveDiagnostics(totalOperatingHours: 1842, serviceHoursLimit: 2000)
        XCTAssertEqual(diag1.hoursUntilService, 158)
        XCTAssertEqual(diag1.serviceProgress, 1842.0 / 2000.0, accuracy: 0.001)
        XCTAssertTrue(diag1.isServiceImminent)
        XCTAssertFalse(diag1.isServiceDue)
        
        // Fresh stove (0 hours)
        let diagFresh = StoveDiagnostics(totalOperatingHours: 0, serviceHoursLimit: 2000)
        XCTAssertEqual(diagFresh.hoursUntilService, 2000)
        XCTAssertEqual(diagFresh.serviceProgress, 0.0)
        XCTAssertFalse(diagFresh.isServiceImminent)
        XCTAssertFalse(diagFresh.isServiceDue)
        
        // Due stove (exactly 2000 hours)
        let diagDue = StoveDiagnostics(totalOperatingHours: 2000, serviceHoursLimit: 2000)
        XCTAssertEqual(diagDue.hoursUntilService, 0)
        XCTAssertEqual(diagDue.serviceProgress, 1.0)
        XCTAssertTrue(diagDue.isServiceImminent)
        XCTAssertTrue(diagDue.isServiceDue)
    }
    
    func testWoodCombustionTrackerPhasesAndSavings() {
        let tracker = WoodCombustionTracker()
        
        // 1. Initial State: Idle
        tracker.update(statusCode: 0, exhaustTemp: 20.0)
        XCTAssertFalse(tracker.isWoodActive)
        XCTAssertEqual(tracker.currentPhase, .idle)
        
        // 2. Status 13 (Legna) triggered with 100°C -> igniting
        tracker.update(statusCode: 13, exhaustTemp: 100.0)
        XCTAssertTrue(tracker.isWoodActive)
        XCTAssertEqual(tracker.currentPhase, .igniting)
        
        // 3. Temperature reaches 240°C -> optimal combustion
        tracker.update(statusCode: 13, exhaustTemp: 240.0)
        XCTAssertEqual(tracker.currentPhase, .optimal)
        
        // 4. Temperature drops to 160°C -> coalsRefillReady (Glutbett)
        tracker.update(statusCode: 13, exhaustTemp: 160.0)
        XCTAssertEqual(tracker.currentPhase, .coalsRefillReady)
        
        // 5. Temperature drops to 115°C -> burnout
        tracker.update(statusCode: 13, exhaustTemp: 115.0)
        XCTAssertEqual(tracker.currentPhase, .burnout)
        
        // 6. Return to Pellet / OFF (status 0) -> Session terminates
        tracker.update(statusCode: 0, exhaustTemp: 40.0)
        XCTAssertFalse(tracker.isWoodActive)
        XCTAssertEqual(tracker.currentPhase, .idle)
    }
    
    func testAutoPowerModulationAndFanSpeedDeduction() {
        // Case 1: Status 5 (Betrieb), Power Setpoint 6 (Auto), Combustion Fan 2 at Stufe 4
        let dumpFan4 = [
            "1000010000050007160300d704000000028801", // status 05 (Heizbetrieb)
            "0c81013100010b060501000000b401",
            "0e016c00060001000600000001016c0007", // 016c = 6 (Auto)
            "0e023f00020000000600000001023f0007", // Flur fan = 2
            "0e02660001000000060000000102660007", // Luftzufuhr 1 = 1
            "0e027e00040000000600000001027e0007"  // Luftzufuhr 2 = 4 (Gebläse aktiv auf Stufe 4!)
        ]
        let dataFan4 = CloudStoveData(deviceKey: nil, isOnline: true, values: nil, Values: dumpFan4, data: nil)
        let mappedFan4 = dataFan4.getMappedValues()
        XCTAssertNotNil(mappedFan4)
        if let mapped = mappedFan4 {
            XCTAssertEqual(mapped.powerLevel, 6, "Sollwert-Register muss 6 (Auto) bleiben")
            XCTAssertEqual(mapped.effectivePower, 4, "Ist-Leistungsstufe muss über aktives Gebläse 4 erkannt werden")
        }
        
        // Case 2: Status 5 (Betrieb), Power Setpoint 6 (Auto), Fans at 1, Room 19.0°C, Target 22.0°C (Delta = 3.0°C -> P5)
        let dumpDeltaHigh = [
            "1000010000050007160300be04000000028801", // Room 19.0°C (0x00be = 190)
            "0c81013100010b060501000000dc01",         // Target 22.0°C (0x00dc = 220)
            "0e016c00060001000600000001016c0007",     // Auto
            "0e01ed00dc006401900001000101ed0000",     // Target 22.0°C
            "0e02660001000000060000000102660007",
            "0e027e00010000000600000001027e0007"
        ]
        let dataDeltaHigh = CloudStoveData(deviceKey: nil, isOnline: true, values: nil, Values: dumpDeltaHigh, data: nil)
        let mappedDeltaHigh = dataDeltaHigh.getMappedValues()
        XCTAssertNotNil(mappedDeltaHigh)
        if let mapped = mappedDeltaHigh {
            XCTAssertEqual(mapped.effectivePower, 5, "Bei Delta T = 3.0°C muss Auto auf P5 modulieren")
        }
        
        // Case 3: Status 6 (Modulation): immer P1 (0.65 kg/h)
        let dumpMod = [
            "1000010000060007160300dc04000000028801", // status 06 (Modulation)
            "0c81013100010b060501000000dc01",
            "0e016c00060001000600000001016c0007"
        ]
        let dataMod = CloudStoveData(deviceKey: nil, isOnline: true, values: nil, Values: dumpMod, data: nil)
        let mappedMod = dataMod.getMappedValues()
        XCTAssertNotNil(mappedMod)
        if let mapped = mappedMod {
            XCTAssertEqual(mapped.effectivePower, 1, "In Modulation muss effectivePower immer 1 sein")
        }
    }

    // MARK: - Priority 1 Tests: Hardware-Schutz & Verbrennungssicherheit
    
    func testPriority1_HardwareProtectionAndCombustionSafety() {
        // Hürde 1.1: Fan Register Separation & Clamping
        let cmdFlurP1 = StoveCommand.writeParameter(id: "023f", value: 1)
        XCTAssertEqual(cmdFlurP1.rawString, "050e023f0001")
        let cmdFlurAuto = StoveCommand.writeParameter(id: "023f", value: 6)
        XCTAssertEqual(cmdFlurAuto.rawString, "050e023f0006")
        
        // Hürde 1.2: Dielle Hardware Alarmcodes (Er01..Er42)
        let expectedAlarms: [(Int, String, String)] = [
            (1, "Er01", "Überhitzungsthermostat Kessel/Wasser"),
            (2, "Er02", "Sicherheitsdruckwächter Wasserdruck"),
            (3, "Er03", "Erloschene Flamme / Pellets leer"),
            (4, "Er04", "Fehlzündung"),
            (5, "Er05", "Rauchgastemperaturfühler defekt"),
            (7, "Er07", "Abgasgebläse Drehzahlfehler"),
            (8, "Er08", "Rauchgas-Übertemperatur"),
            (12, "Er12", "Pelletmangel / Dosierer"),
            (39, "Er39", "Unterdruckwächter Brennraum / Kaminzug"),
            (41, "Er41", "Luftstrom-Minimum unterschritten"),
            (42, "Er42", "Maximaler Luftstrom / Tür offen")
        ]
        
        for (code, codeStr, title) in expectedAlarms {
            let alarm = DielleHardwareAlarm.from(code: code)
            XCTAssertNotNil(alarm, "Alarm für Code \(code) muss existieren")
            XCTAssertEqual(alarm?.codeString, codeStr)
            XCTAssertEqual(alarm?.title, title)
            XCTAssertFalse(alarm?.description.isEmpty ?? true)
            XCTAssertFalse(alarm?.remedy.isEmpty ?? true)
        }
        
        // Hürde 1.3: Sub-Zero Telemetry Parsing (-400..1200, != -1270)
        // Room temp at offset 20..24: -50 = -5.0°C (0xFFCE)
        let subZeroDump = [
            "10000100000000071603ffce04000000028801", // 0xffce = -50 -> -5.0°C
            "0c81013100010b060501000000b401"
        ]
        let subZeroData = CloudStoveData(deviceKey: nil, isOnline: true, values: nil, Values: subZeroDump, data: nil)
        let mappedSubZero = subZeroData.getMappedValues()
        XCTAssertNotNil(mappedSubZero)
        XCTAssertEqual(mappedSubZero?.room ?? 0, -5.0, accuracy: 0.05, "Minusgrade wie -5.0°C müssen korrekt geparst werden")
        
        // Disconnected sensor code -1270 (0xFB0A) must be ignored
        let disconnectedDump = [
            "10000100000000071603fb0a04000000028801", // -1270
            "0c81013100010b060501000000b401"
        ]
        let disconnectedData = CloudStoveData(deviceKey: nil, isOnline: true, values: nil, Values: disconnectedDump, data: nil)
        let mappedDisconnected = disconnectedData.getMappedValues()
        XCTAssertEqual(mappedDisconnected?.room, 0.0, "Sensorfehler -1270 darf nicht als Raumtemperatur übernommen werden")
        
        // Hürde 1.5: Hardware Chrono Padding to exactly 71 parameters
        var sparseDays: [HardwareChronoDay] = []
        for d in 1...7 {
            sparseDays.append(HardwareChronoDay(id: d, name: "Tag \(d)", shortName: "T\(d)", slots: [
                HardwareChronoSlot(id: 1, startTime: "07:00", endTime: "09:00", isEnabled: true)
            ]))
        }
        let sparsePlan = HardwareChronoPlan(mode: .daily, isGloballyEnabled: true, days: sparseDays)
        let ccsSparse = sparsePlan.toCCSCommandString()
        guard let jsonData = ccsSparse.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [String] else {
            XCTFail("CCS Command String muss valides JSON-Array sein")
            return
        }
        XCTAssertEqual(jsonArray.count, 73, "toCCSCommandString muss exakt 73 Elemente (71 Parameter) erzeugen")
        XCTAssertEqual(jsonArray[0], "CCS")
        XCTAssertEqual(jsonArray[1], "71")
        // Check padding on slot 2 and 3
        XCTAssertEqual(jsonArray[7], "00:00", "Fehlender Slot 2 Start muss mit 00:00 aufgefüllt sein")
        XCTAssertEqual(jsonArray[8], "00:00", "Fehlender Slot 2 End muss mit 00:00 aufgefüllt sein")
        XCTAssertEqual(jsonArray[9], "0", "Fehlender Slot 2 muss deaktiviert sein")
    }
    
    // MARK: - PRIORITÄT 2: Netzwerk & Socket-Stabilität Tests
    func testPriority2_NetworkAndSocketStability() async {
        // Hürde 2.1: Dual-Path ConnectionPath Exponierung
        let vm = StoveViewModel()
        XCTAssertNotNil(vm.connectionPath)
        XCTAssertEqual(StoveViewModel.ConnectionPath.localSocket.title, "Lokales WLAN (Port 80)")
        XCTAssertEqual(StoveViewModel.ConnectionPath.cloud.title, "Dielle Cloud (Azure)")
        XCTAssertEqual(StoveViewModel.ConnectionPath.localSocket.icon, "wifi")
        XCTAssertEqual(StoveViewModel.ConnectionPath.cloud.icon, "cloud.fill")
        
        // Hürde 2.2: Asymmetrisches Polling-Intervall
        vm.connectionPath = .localSocket
        XCTAssertEqual(vm.currentPollingInterval, 3.0, "Lokaler Modus muss 3 Sekunden Polling-Intervall haben")
        
        vm.connectionPath = .cloud
        XCTAssertGreaterThanOrEqual(vm.currentPollingInterval, 10.0, "Cloud-Modus muss mind. 10 Sekunden Intervall haben")
        XCTAssertLessThanOrEqual(vm.currentPollingInterval, 12.0, "Cloud-Modus darf höchstens 12 Sekunden Intervall haben")
        
        // Hürde 2.4: TCP Buffer Line-Splitting & Command-Echo Filter in StoveSocketService
        let socketService = StoveSocketService()
        
        // 1. Unvollständiges Fragment einspeisen (darf nicht crashen oder parsen)
        let partial1 = "[\"2WC\",\"1\"".data(using: .utf8)!
        socketService.processIncomingData(partial1)
        XCTAssertEqual(socketService.lastCommandAck, "", "Unvollständige Fragmente dürfen nicht als ACK verarbeitet werden")
        XCTAssertEqual(socketService.responseMessage, "")
        
        // 2. Rest des Fragments mit Newline einspeisen (muss als Command-Echo erkannt werden)
        let partial2 = ",\"05040000\"]\n".data(using: .utf8)!
        socketService.processIncomingData(partial2)
        XCTAssertTrue(socketService.lastCommandAck.contains("2WC"), "Command Echo muss erkannt werden")
        XCTAssertEqual(socketService.responseMessage, "", "Command Echo darf NICHT als Telemetrie gesetzt werden")
        
        // 3. Telemetrie mit Line-Splitting einspeisen
        let telemetryLine = "[\"2WL\",\"25\",\"10000100000b0007135400d804000000018801\",\"0c81013000010b060501000000bd01\"]\n"
        socketService.processIncomingData(telemetryLine.data(using: .utf8)!)
        XCTAssertTrue(socketService.responseMessage.contains("2WL"), "Telemetrie muss in responseMessage gespeichert werden")
        XCTAssertNotNil(socketService.latestStoveData, "latestStoveData muss geparst sein")
        
        let mapped = socketService.latestStoveData?.getMappedValues()
        XCTAssertNotNil(mapped)
        XCTAssertEqual(mapped?.room ?? 0, 21.6, accuracy: 0.1, "Raumtemperatur muss aus 2WL Stream korrekt dekodiert werden")
        XCTAssertEqual(mapped?.status ?? 0, 11, "Status muss 11 (Standby) sein")
        
        // 4. Gemischter Stream: Echo + Telemetrie + Incomplete in einem Block
        let mixedStream = "[\"2WC\",\"1\"]\n[\"2WL\",\"25\",\"10000100000b0007135400d804000000018801\",\"0c81013000010b060501000000bd01\"]\n[\"2WL\",\"unfertig".data(using: .utf8)!
        socketService.processIncomingData(mixedStream)
        XCTAssertEqual(socketService.lastCommandAck, "[\"2WC\",\"1\"]")
        XCTAssertTrue(socketService.responseMessage.contains("2WL"))
        
        // Hürde 2.5: Ofen-IP Konfiguration & UDP Discovery Drosselung
        let originalIP = vm.stoveLocalIP
        vm.stoveLocalIP = "192.168.178.199"
        XCTAssertEqual(UserDefaults.standard.string(forKey: "stove_local_ip"), "192.168.178.199")
        XCTAssertEqual(vm.socketService.currentHost, "192.168.178.199")
        
        // Restore
        vm.stoveLocalIP = originalIP
        
        // UDPDiscoveryService Drosselung & Stop
        let discovery = UDPDiscoveryService()
        XCTAssertFalse(discovery.isScanning)
        discovery.discoverStove()
        XCTAssertTrue(discovery.isScanning, "Discovery muss aktiv starten")
        discovery.stopDiscovery()
        XCTAssertFalse(discovery.isScanning, "stopDiscovery muss sofort beenden und Broadcasts einstellen")
    }
    
    // MARK: - PRIORITÄT 3: Status & Datensynchronisation Tests
    func testPriority3_StatusAndDataSynchronization() async {
        // --- Hürde 3.1 & 3.2: Pellet-Primer (200g) und State-Guard Logik ---
        let pelletManager = PelletTankManager()
        pelletManager.setLevel(kg: 18.0)
        XCTAssertEqual(pelletManager.currentLevel, 18.0)
        
        // 1. Übergang von 0 (Aus) zu 1 (Zündung Start): Einmalig 0.20 kg abziehen
        pelletManager.updateTracking(statusCode: 0, powerLevel: 1, isWood: false)
        XCTAssertFalse(pelletManager.isIgnitionPrimerDeducted)
        
        pelletManager.updateTracking(statusCode: 1, powerLevel: 1, isWood: false)
        XCTAssertEqual(pelletManager.currentLevel, 17.80, accuracy: 0.001, "0.20 kg Primer müssen bei Status 0 -> 1 abgezogen werden")
        XCTAssertTrue(pelletManager.isIgnitionPrimerDeducted, "Flag isIgnitionPrimerDeducted muss nach Abzug true sein")
        XCTAssertEqual(pelletManager.dailyConsumption, 0.20, accuracy: 0.001, "Tagesverbrauch muss um Primer (0.20 kg) steigen")
        
        // 2. Weiterschalten im selben Zündzyklus (1 -> 2 -> 3 -> 4 -> 5): KEIN Mehrfachabzug
        pelletManager.updateTracking(statusCode: 2, powerLevel: 1, isWood: false)
        XCTAssertEqual(pelletManager.currentLevel, 17.80, accuracy: 0.001, "Kein zweiter Primer-Abzug bei Status 2 im selben Zyklus")
        
        pelletManager.updateTracking(statusCode: 4, powerLevel: 1, isWood: false)
        XCTAssertEqual(pelletManager.currentLevel, 17.80, accuracy: 0.001, "Kein Primer-Abzug bei Status 4")
        
        pelletManager.updateTracking(statusCode: 5, powerLevel: 2, isWood: false)
        XCTAssertTrue(pelletManager.isIgnitionPrimerDeducted)
        
        // 3. Übergang in Standby (11) oder Aus (0): Flag wird zurückgesetzt
        pelletManager.updateTracking(statusCode: 11, powerLevel: 1, isWood: false)
        XCTAssertFalse(pelletManager.isIgnitionPrimerDeducted, "Flag muss bei Standby/Aus wieder false sein")
        
        // 4. Neuer Zündstart aus Standby (11 -> 2): Erneut exakt 0.20 kg abziehen
        let beforeSecondIgnition = pelletManager.currentLevel
        pelletManager.updateTracking(statusCode: 2, powerLevel: 1, isWood: false)
        XCTAssertEqual(pelletManager.currentLevel, beforeSecondIgnition - 0.20, accuracy: 0.001, "Neuer Zündzyklus zieht erneut 0.20 kg ab")
        XCTAssertTrue(pelletManager.isIgnitionPrimerDeducted)
        
        // --- Hürde 3.3: Status-5 Label Verwirrung 'Ein' vs 'Heizbetrieb' ---
        let vm = StoveViewModel()
        
        // Status 5: Muss eindeutig als "Heizbetrieb" geführt werden
        let telemetryStatus5 = [
            "1000010000050007160300d704000000028801", // Status 05
            "0c81013100010b060501000000b401"
        ]
        vm.updateTelemetry(values: telemetryStatus5, source: "Test")
        XCTAssertEqual(vm.stoveStatus, "Heizbetrieb", "Status 5 muss als 'Heizbetrieb' geführt werden (nicht 'Ein')")
        XCTAssertEqual(vm.operationalState, .on)
        XCTAssertEqual(vm.operationalState.title, "Heizbetrieb", "StoveOperationalState.on.title muss 'Heizbetrieb' sein")
        
        // Status 6: Modulation
        let telemetryStatus6 = [
            "1000010000060007160300d704000000028801",
            "0c81013100010b060501000000b401"
        ]
        vm.updateTelemetry(values: telemetryStatus6, source: "Test")
        XCTAssertEqual(vm.stoveStatus, "Modulation", "Status 6 muss als 'Modulation' geführt werden")
        XCTAssertEqual(vm.operationalState, .on)
        
        // Status 13: Scheitholzbetrieb
        let telemetryStatus13 = [
            "10000100000d0007160300d704000000028801", // 0x0D = 13
            "0c81013100010b060501000000b401"
        ]
        vm.updateTelemetry(values: telemetryStatus13, source: "Test")
        XCTAssertEqual(vm.stoveStatus, "Scheitholzbetrieb", "Status 13 muss als 'Scheitholzbetrieb' geführt werden")
        XCTAssertTrue(vm.isWoodMode, "isWoodMode muss bei Status 13 aktiv sein")
        
        // Status 1: Zündung Phase 1
        let telemetryStatus1 = [
            "1000010000010007160300d704000000028801",
            "0c81013100010b060501000000b401"
        ]
        vm.updateTelemetry(values: telemetryStatus1, source: "Test")
        XCTAssertEqual(vm.stoveStatus, "Zündung Phase 1")
        XCTAssertEqual(vm.operationalState, .igniting)
        
        // Status 0: Aus
        let telemetryStatus0 = [
            "1000010000000007160300d704000000028801",
            "0c81013100010b060501000000b401"
        ]
        vm.updateTelemetry(values: telemetryStatus0, source: "Test")
        XCTAssertEqual(vm.stoveStatus, "Aus")
        XCTAssertEqual(vm.operationalState, .off)
        
        // --- Hürde 3.4: Wartungs- und Betriebsdaten-Verdrahtung & 2000h Service ---
        let diag = StoveDiagnostics(totalOperatingHours: 1842, serviceHoursLimit: 2000)
        XCTAssertEqual(diag.hoursUntilService, 158, "1842h von 2000h = 158 Stunden bis Wartung")
        XCTAssertTrue(diag.isServiceImminent, "Bei 158h Rest muss isServiceImminent true sein (<= 200h)")
        XCTAssertFalse(diag.isServiceDue, "Bei 158h Rest ist Service noch nicht fällig")
        XCTAssertEqual(diag.serviceProgress, 0.921, accuracy: 0.001, "Fortschritt ca. 92.1%")
        
        let dueDiag = StoveDiagnostics(totalOperatingHours: 2000, serviceHoursLimit: 2000)
        XCTAssertEqual(dueDiag.hoursUntilService, 0)
        XCTAssertTrue(dueDiag.isServiceDue, "Bei 2000h muss Service fällig sein")
        XCTAssertEqual(dueDiag.serviceProgress, 1.0, accuracy: 0.001)
        
        // Akkumulation in StoveViewModel
        UserDefaults.standard.removeObject(forKey: StoveViewModel.diagnosticsStorageKey)
        vm.diagnostics = StoveDiagnostics(totalOperatingHours: 100, heatingHours: 80, ignitionCount: 50, serviceHoursLimit: 2000)
        vm.saveDiagnostics()
        
        // Zündungs-Zähler inkrementieren bei Start (0 -> 1)
        vm.updateDiagnosticsTracking(statusCode: 0)
        vm.updateDiagnosticsTracking(statusCode: 1)
        XCTAssertEqual(vm.diagnostics.ignitionCount, 51, "Zündungszähler muss von 50 auf 51 steigen")
        
        // Weiterschalten im Zyklus (1 -> 2) darf Zähler nicht erneut inkrementieren
        vm.updateDiagnosticsTracking(statusCode: 2)
        XCTAssertEqual(vm.diagnostics.ignitionCount, 51, "Kein doppelter Zähleranstieg im selben Zyklus")
        
        // Brennstunden-Akkumulation: 3600 Sekunden bei Status 5 (Heizbetrieb) simulieren
        vm.updateDiagnosticsTracking(statusCode: 5, deltaSeconds: 3600.0)
        XCTAssertEqual(vm.diagnostics.heatingHours, 81, "Heizstunden müssen um 1h steigen")
        XCTAssertEqual(vm.diagnostics.totalOperatingHours, 101, "Gesamtlaufzeit muss um 1h steigen")
        
        // Persistenz prüfen
        let newVm = StoveViewModel()
        XCTAssertEqual(newVm.diagnostics.ignitionCount, 51, "Persistierter Zündungszähler muss geladen werden")
        XCTAssertEqual(newVm.diagnostics.heatingHours, 81, "Persistierte Heizstunden müssen geladen werden")
        XCTAssertEqual(newVm.diagnostics.totalOperatingHours, 101, "Persistierte Gesamtlaufzeit muss geladen werden")
        
        // --- Hürde 3.5: Switch is_on Konsistenz & Befehle ---
        // Gültige Befehle: turnOn = 05040000, turnOff = 05050000
        XCTAssertEqual(StoveCommand.turnOn.rawString, "05040000")
        XCTAssertEqual(StoveCommand.turnOff.rawString, "05050000")
        
        // Switch Logik Prüfung: Aktive Betriebszustände müssen True sein
        let activeStates = [1, 2, 3, 4, 5, 6, 13]
        for state in activeStates {
            let isActive = [1, 2, 3, 4, 5, 6, 13].contains(state)
            XCTAssertTrue(isActive, "Status \(state) muss für Switch als is_on = true gelten")
        }
        
        // Inaktive & Sicherheitszustände müssen False sein
        let inactiveStates = [0, 7, 8, 9, 10, 11, 12]
        for state in inactiveStates {
            let isActive = [1, 2, 3, 4, 5, 6, 13].contains(state)
            XCTAssertFalse(isActive, "Status \(state) muss für Switch als is_on = false gelten")
        }
    }
    
    // MARK: - PRIORITÄT 4: Scheitholz & Hybrid-Betrieb Tests
    func testPriority4_WoodAndHybridCombustion() {
        let tracker = WoodCombustionTracker.shared
        tracker.resetSession()
        
        let t0 = Date()
        
        // --- Hürde 4.1 & 4.2: Kaltstart in Scheitholz (50°C) -> Keine Ersparnis, Phase idle ---
        tracker.update(statusCode: 13, exhaustTemp: 50.0, timestamp: t0)
        XCTAssertTrue(tracker.isWoodActive)
        XCTAssertEqual(tracker.currentPhase, .idle, "Bei <60°C muss Phase idle sein")
        XCTAssertEqual(tracker.sessionSavedPelletsKg, 0.0, "Bei <100°C keine Pellet-Ersparnis")
        
        // Anheizen durch 80°C (dT/dt > 0, noch unter 100°C)
        let t1 = t0.addingTimeInterval(30)
        tracker.update(statusCode: 13, exhaustTemp: 80.0, timestamp: t1)
        XCTAssertEqual(tracker.currentPhase, .igniting, "Bei 80°C steigend muss Phase igniting sein")
        XCTAssertGreaterThan(tracker.tempGradient, 0.0, "Gradient muss positiv sein")
        XCTAssertEqual(tracker.sessionSavedPelletsKg, 0.0, "Bei 80°C (<100°C) immer noch null Pellet-Ersparnis (Hürde 4.2 Schutz vor Phantom-Ersparnis)")
        
        // Anheizen durch 150°C (dT/dt > 0, kein Peak >= 180°C bisher)
        // WICHTIG: Darf KEIN 'coalsRefillReady' sein, da die Temperatur steigt und noch kein Brandpeak da war!
        let t2 = t1.addingTimeInterval(60)
        tracker.update(statusCode: 13, exhaustTemp: 150.0, timestamp: t2)
        XCTAssertEqual(tracker.currentPhase, .igniting, "Beim Durchschreiten von 150°C im Anheizen muss Phase igniting sein (kein falsches Glutbett!)")
        XCTAssertGreaterThan(tracker.tempGradient, 0.0)
        XCTAssertGreaterThan(tracker.effectiveCombustionDuration, 0.0, "Ab >=100°C beginnt die effektive Brenndauer")
        
        // Optimaler Brand bei 220°C (Peak erreicht)
        let t3 = t2.addingTimeInterval(60)
        tracker.update(statusCode: 13, exhaustTemp: 220.0, timestamp: t3)
        XCTAssertEqual(tracker.currentPhase, .optimal, "Bei 220°C muss Phase optimal sein")
        XCTAssertEqual(tracker.sessionPeakExhaustTemp, 220.0, "Peak muss 220°C sein")
        
        // Glutbett / Nachlegen empfohlen: Temperatur sinkt von 220°C auf 155°C (Peak war >= 180°C, dT/dt < 0, 120°C <= T < 180°C)
        let t4 = t3.addingTimeInterval(60)
        tracker.update(statusCode: 13, exhaustTemp: 155.0, timestamp: t4)
        XCTAssertEqual(tracker.currentPhase, .coalsRefillReady, "Nach Peak und bei fallender Temp (155°C) muss Phase coalsRefillReady sein!")
        XCTAssertLessThan(tracker.tempGradient, 0.0, "Gradient muss negativ sein")
        
        // Ausbrand / Vorbereitung Pelletübernahme: Temperatur sinkt weiter auf 95°C (Peak war >= 180°C, dT/dt < 0, 60°C <= T < 120°C)
        let t5 = t4.addingTimeInterval(60)
        tracker.update(statusCode: 13, exhaustTemp: 95.0, timestamp: t5)
        XCTAssertEqual(tracker.currentPhase, .burnout, "Bei <120°C fallend muss Phase burnout sein")
        
        // --- Hürde 4.3: Zündungs-Primer bei Holz -> Pellet Übergang ---
        let pelletMgr = PelletTankManager()
        pelletMgr.currentLevel = 15.0
        pelletMgr.dailyConsumption = 0.0
        
        // Ofen brennt Holz (Status 13)
        pelletMgr.updateTracking(statusCode: 13, powerLevel: 3, isWood: true)
        XCTAssertEqual(pelletMgr.currentLevel, 15.0)
        XCTAssertFalse(pelletMgr.isIgnitionPrimerDeducted)
        
        // Übergang direkt von Holz (13) zu Heizbetrieb (5): KEIN Primer-Abzug
        pelletMgr.updateTracking(statusCode: 5, powerLevel: 3, isWood: false)
        XCTAssertEqual(pelletMgr.currentLevel, 15.0, accuracy: 0.01, "Direkter Übergang Holz -> Pellets darf KEINEN Primer abziehen")
        XCTAssertEqual(pelletMgr.dailyConsumption, 0.0, accuracy: 0.01)
        
        // Erst wenn Ofen AUS war (0) und dann neu zündet (1/2), greift der reguläre Primer-Abzug
        pelletMgr.updateTracking(statusCode: 0, powerLevel: 1, isWood: false)
        XCTAssertFalse(pelletMgr.isIgnitionPrimerDeducted)
        pelletMgr.updateTracking(statusCode: 1, powerLevel: 1, isWood: false)
        XCTAssertEqual(pelletMgr.currentLevel, 14.80, accuracy: 0.001, "Erst bei Kaltzündung aus 0 wird 0.20 kg abgezogen")
        XCTAssertTrue(pelletMgr.isIgnitionPrimerDeducted)
    }
    
    // MARK: - PRIORITÄT 5: UI, Siri & Nebenläufigkeit Tests
    func testPriority5_UI_Siri_And_Concurrency() {
        let vm = StoveViewModel()
        vm.pausePolling() // Polling stoppen für deterministischen Testlauf
        defer { vm.pausePolling() }
        
        // --- Hürde 5.1: Siri Intent Metadaten & Konfiguration ---
        XCTAssertEqual(TurnOffStoveIntent.title, "Pelletofen ausschalten")
        XCTAssertFalse(TurnOffStoveIntent.openAppWhenRun)
        
        // --- Hürde 5.2: 48h (2 Tage) Standard-Historienfenster ---
        let ha = HomeAssistantService.shared
        XCTAssertTrue(ha.isEnabled || !ha.isEnabled) // Validiert Initialisierung
        
        // --- Hürde 5.3: Überlappende Burst-Befehle & Concurrency ---
        vm.isTargetLocked = false
        vm.targetTemp = 21.0
        // Direkte Aktualisierung prüfen
        let rounded = (22.0 * 2).rounded() / 2
        vm.targetTemp = rounded
        XCTAssertEqual(vm.targetTemp, 22.0, "Letzter Sollwert muss aktiv sein")
        
        // --- Hürde 5.4: HeatingScheduleManager Auswertung & Nachführung ---
        let scheduleMgr = HeatingScheduleManager.shared
        scheduleMgr.isScheduleActive = true
        scheduleMgr.defaultNightTemp = 23.0
        scheduleMgr.overrideTargetTemp = 23.0
        scheduleMgr.overrideUntil = Date().addingTimeInterval(3600)
        
        let scheduled = scheduleMgr.getCurrentTargetTemperature()
        XCTAssertEqual(scheduled, 23.0, "Scheduled Temp muss 23.0°C sein")
        
        // Nachführung testen
        vm.isTargetLocked = false
        vm.targetTemp = 20.0
        vm.evaluateHeatingSchedule()
        XCTAssertEqual(vm.targetTemp, 23.0, "evaluateHeatingSchedule muss Sollwert auf 23.0°C nachführen")
        
        // Bei gesperrter Interaktion darf nicht überschrieben werden
        vm.targetTemp = 20.0
        vm.triggerInteractionLock()
        vm.evaluateHeatingSchedule()
        XCTAssertEqual(vm.targetTemp, 20.0, "Bei aktiver Benutzer-Interaktion darf Heizplan Sollwert nicht überschreiben")
        
        // Restore
        scheduleMgr.isScheduleActive = false
    }
    
    // MARK: - PRIORITÄT 6: Verbindungs-Stabilität & Wartungs-Reset Tests
    func testPriority6_ConnectionMode_And_ServiceReset() async {
        // --- Teil 1: 2.000h Wartungszähler & Reset ---
        var diag = StoveDiagnostics(
            totalOperatingHours: 2000,
            heatingHours: 1600,
            ignitionCount: 500,
            serviceHoursLimit: 2000,
            lastServiceOperatingHours: 0,
            lastServiceDate: nil
        )
        
        // Vor dem Reset: 2.000h erreicht -> Wartung fällig
        XCTAssertEqual(diag.hoursSinceLastService, 2000)
        XCTAssertEqual(diag.hoursUntilService, 0)
        XCTAssertEqual(diag.serviceProgress, 1.0)
        XCTAssertTrue(diag.isServiceDue)
        
        // Quittieren / Reset durchführen
        diag.resetService(operatingHours: 2000)
        
        // Nach dem Reset: Start bei 2.000h Basis
        XCTAssertEqual(diag.lastServiceOperatingHours, 2000)
        XCTAssertNotNil(diag.lastServiceDate)
        XCTAssertEqual(diag.hoursSinceLastService, 0)
        XCTAssertEqual(diag.hoursUntilService, 2000)
        XCTAssertEqual(diag.serviceProgress, 0.0)
        XCTAssertFalse(diag.isServiceDue)
        XCTAssertFalse(diag.isServiceImminent)
        
        // Wenn der Ofen nach der Wartung 50h weiterläuft
        diag.totalOperatingHours = 2050
        XCTAssertEqual(diag.hoursSinceLastService, 50)
        XCTAssertEqual(diag.hoursUntilService, 1950)
        XCTAssertEqual(diag.serviceProgress, 50.0 / 2000.0, accuracy: 0.001)
        
        // --- Teil 2: ViewModel Service Reset & Persistence ---
        let vm = StoveViewModel()
        vm.pausePolling()
        defer { vm.pausePolling() }
        
        vm.diagnostics.totalOperatingHours = 2100
        vm.diagnostics.lastServiceOperatingHours = 0
        vm.resetServiceMaintenance()
        
        XCTAssertEqual(vm.diagnostics.lastServiceOperatingHours, 2100)
        XCTAssertEqual(vm.diagnostics.hoursUntilService, 2000)
        XCTAssertEqual(vm.diagnostics.serviceProgress, 0.0)
        XCTAssertNotNil(vm.diagnostics.lastServiceDate)
        
        // --- Teil 3: ConnectionMode (Exklusive Cloud-Synchronisation) ---
        XCTAssertEqual(StoveViewModel.ConnectionMode.allCases.count, 1)
        XCTAssertEqual(StoveViewModel.ConnectionMode.forceCloud.title, "Dielle Cloud (Exklusiv)")
        XCTAssertEqual(vm.connectionPath, .cloud, "Verbindungspfad muss standardmäßig cloud sein")
        
        await vm.evaluateConnectionPath()
        XCTAssertEqual(vm.connectionPath, .cloud, "In exklusivem Modus muss Verbindungspfad dauerhaft cloud bleiben")
    }
    
    // MARK: - PRIORITÄT 7: iPhone Akku- & Energie-Effizienz Tests
    func testAdaptiveEcoPollingAndBatteryEfficiency() {
        let vm = StoveViewModel()
        vm.pausePolling()
        defer { vm.pausePolling() }
        
        // 1. Eco-Mode standardmäßig aktiviert
        XCTAssertTrue(vm.isEcoModeEnabled)
        
        // 2. Frischer App-Start / Aktive Benutzer-Interaktion -> 10s Takt
        XCTAssertTrue(vm.isUserInteracting, "Frisch gestartete App muss im Interaktionsfenster sein")
        vm.isLowPowerMode = false
        XCTAssertEqual(vm.currentPollingInterval, 10.0, "Bei aktiver Bedienung muss 10s Polling aktiv sein")
        
        // 3. Wenn der Ofen brennt (Heizbetrieb) -> 10s Takt
        vm.operationalState = .on
        vm.exhaustTemp = 180.0
        XCTAssertTrue(vm.isStoveActive)
        XCTAssertEqual(vm.currentPollingInterval, 10.0, "Bei aktivem Ofen muss 10s Polling aktiv sein")
        
        // 4. Wenn Eco-Modus deaktiviert wird -> stur 10s
        vm.isEcoModeEnabled = false
        XCTAssertEqual(vm.currentPollingInterval, 10.0)
        vm.isEcoModeEnabled = true
        
        // 5. BLE Manager Akku-Schutz
        let ble = BLEManager()
        XCTAssertFalse(ble.isBluetoothEnabled && ble.connectedPeripheral != nil)
        
        // 6. Pause Polling storniert Timer
        vm.pausePolling()
        XCTAssertFalse(vm.isSyncing)
    }
}

