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
}

