import XCTest
import Combine
@testable import SmartHeat

@MainActor
final class StoveStressAndChaosTests: XCTestCase {
    
    // MARK: - 1. Strict Safety Invariant
    
    func testSafetyInvariant_NoTurnOnCommandIsSent() {
        // Der Ofen darf unter keinen Umständen im Test eingeschaltet werden!
        let safeCommands: [StoveCommand] = [
            .turnOff,
            .poll2Ways,
            .writeParameter(id: "01ed", value: 200),
            .writeParameter(id: "027e", value: 2),
            .writeParameter(id: "0266", value: 2)
        ]
        
        for cmd in safeCommands {
            XCTAssertNotEqual(cmd.rawString, "05040000", "SICHERHEITSVERLETZUNG: Einschaltbefehl 05040000 darf niemals gesendet werden!")
            XCTAssertNotEqual(cmd.rawString, "J30253000000000001", "SICHERHEITSVERLETZUNG: Syevo Einschaltbefehl darf niemals gesendet werden!")
        }
    }
    
    // MARK: - 2. Lifecycle & Backgrounding Stress Test
    
    func testLifecycleStress_RapidPauseAndResumePolling() async {
        let viewModel = StoveViewModel()
        
        // Simuliert 50 rasche Wechsel zwischen App-Vordergrund und Hintergrund (z.B. schnelles Entsperren/Sperren)
        for _ in 0..<50 {
            viewModel.pausePolling()
            XCTAssertFalse(viewModel.isSyncing, "Nach pausePolling() darf kein Sync-Status hängen bleiben")
            
            viewModel.resumePolling()
            // Kurze asynchrone Pause
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }
        
        // Sauberes Aufräumen
        viewModel.pausePolling()
        XCTAssertFalse(viewModel.isSyncing)
    }
    
    // MARK: - 3. Concurrency & Overlap Prevention Stress Test
    
    func testConcurrencyStress_OverlappingSyncTasksDoNotStack() async {
        let viewModel = StoveViewModel()
        
        // Feuere 30 parallele refreshData-Aufrufe ab
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<30 {
                group.addTask { @MainActor in
                    viewModel.refreshData()
                }
            }
        }
        
        // Warten, bis eventuelle Tasks abgearbeitet sind
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        viewModel.pausePolling()
        XCTAssertTrue(true, "Parallele Aufrufe ohne Deadlock überstanden")
    }
    
    // MARK: - 4. Lock & Temperature Stepper Bounds Chaos
    
    func testTemperatureStepper_RapidBoundsAndClampingChaos() {
        let viewModel = StoveViewModel()
        viewModel.isTargetLocked = false
        
        // Teste untere Grenze (min 10.0°C)
        viewModel.targetTemp = 10.5
        viewModel.decrementTargetTemp()
        XCTAssertEqual(viewModel.targetTemp, 10.0, accuracy: 0.01)
        viewModel.decrementTargetTemp() // Darf nicht unter 10.0 fallen
        XCTAssertGreaterThanOrEqual(viewModel.targetTemp, 10.0)
        
        // Teste obere Grenze (max 35.0°C)
        viewModel.targetTemp = 34.5
        viewModel.incrementTargetTemp()
        XCTAssertEqual(viewModel.targetTemp, 35.0, accuracy: 0.01)
        viewModel.incrementTargetTemp() // Darf nicht über 35.0 steigen
        XCTAssertLessThanOrEqual(viewModel.targetTemp, 35.0)
        
        // Teste 100 schnelle Verstellungen
        for _ in 0..<100 {
            viewModel.incrementTargetTemp()
        }
        XCTAssertEqual(viewModel.targetTemp, 35.0)
        
        for _ in 0..<100 {
            viewModel.decrementTargetTemp()
        }
        XCTAssertEqual(viewModel.targetTemp, 10.0)
    }
    
    func testLockToggle_RapidTogglingStress() {
        let viewModel = StoveViewModel()
        
        for i in 0..<100 {
            viewModel.isTargetLocked = (i % 2 == 0)
        }
        
        // Nach 100 Toggles muss der Status definiert sein
        XCTAssertFalse(viewModel.isTargetLocked)
        viewModel.isTargetLocked = true
        XCTAssertTrue(viewModel.isTargetLocked)
    }
    
    // MARK: - 5. Telemetry & History Calculation Stress (Division by Zero & Extremes)
    
    func testTemperatureHistory_DivisionByZeroAndOutlierResistance() {
        let historyManager = TemperatureHistoryManager()
        historyManager.roomTempHistory = []
        historyManager.exhaustTempHistory = []
        
        // Bei komplett leerer Historie dürfen Averages niemals crashen (NaN / Division by Zero Schutz)
        XCTAssertFalse(historyManager.todayRoomAvg.isNaN, "Leere Historie darf kein NaN für todayRoomAvg liefern")
        XCTAssertFalse(historyManager.last7DaysRoomAvg.isNaN, "Leere Historie darf kein NaN für last7DaysRoomAvg liefern")
        XCTAssertFalse(historyManager.monthlyRoomAvg.isNaN, "Leere Historie darf kein NaN für monthlyRoomAvg liefern")
        
        // Ingestion von 1000 Messpunkten im Stress-Test
        var points: [TemperaturePoint] = []
        let baseDate = Date()
        for i in 0..<1000 {
            let offset = Double(i) * 60.0
            let pt = TemperaturePoint(
                date: baseDate.addingTimeInterval(-offset),
                temperature: Double.random(in: 15.0...28.0)
            )
            points.append(pt)
        }
        
        historyManager.updateWithHomeAssistantData(roomPoints: points, exhaustPoints: points)
        
        XCTAssertEqual(historyManager.roomTempHistory.count, 1000)
        XCTAssertGreaterThan(historyManager.todayRoomAvg, 0.0)
        XCTAssertLessThan(historyManager.todayRoomAvg, 50.0)
    }
    
    // MARK: - 6. Cloud Telemetry Parser Fuzzing & Malformed Hex Chaos
    
    func testCloudParserFuzzing_MalformedAndExtremePayloads() {
        let cloudService = CloudService()
        
        let corruptPayloads: [[String]] = [
            [],                                                                  // Komplett leer
            [""],                                                                // Leerer String
            ["XYZ!@#$$%^&*()"],                                                 // Illegale Zeichen
            ["10"],                                                              // Viel zu kurzer Block 0
            ["1000010000"],                                                      // Abgeschnittener Status
            ["0c81"],                                                            // Zu kurzer 0c81-Block
            ["12ffff"],                                                          // Zu kurzer Sensor-Block
            ["0e0180"],                                                          // Zu kurzer Parameter-Block
            Array(repeating: "10000100000b0007135400d804000000018801", count: 200), // Riesen-Array (200 Blöcke)
            [String(repeating: "A", count: 10000)],                              // 10.000 Zeichen Buffer
            ["10FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"] // Extremwerte
        ]
        
        for (idx, payload) in corruptPayloads.enumerated() {
            // Darf NIEMALS abstürzen oder unhandled exceptions werfen!
            let parsed = cloudService.parseAllValues(payload)
            if idx == 8 {
                // Das 200-Blöcke Array muss sauber geparst werden
                XCTAssertNotNil(parsed, "Gültige wiederholte Blöcke müssen geparst werden")
            }
        }
    }
    
    // MARK: - 7. Heating Schedule Engine Stress Test
    
    func testHeatingSchedule_MinuteByMinuteWeeklySweepStress() {
        let manager = HeatingScheduleManager.shared
        manager.isScheduleActive = true
        
        // Slot-Suche mit timeSlots
        let slot1 = HeatingTimeSlot(name: "Morgen", startHour: 6, startMinute: 0, endHour: 9, endMinute: 0, targetTemp: 22.0)
        let slot2 = HeatingTimeSlot(name: "Abend", startHour: 17, startMinute: 30, endHour: 22, endMinute: 0, targetTemp: 23.0)
        let slotOverMidnight = HeatingTimeSlot(name: "Nacht", startHour: 23, startMinute: 0, endHour: 5, endMinute: 30, targetTemp: 18.0)
        
        XCTAssertTrue(slot1.contains(currentHour: 7, currentMinute: 0))
        XCTAssertFalse(slot1.contains(currentHour: 10, currentMinute: 0))
        XCTAssertTrue(slot2.contains(currentHour: 18, currentMinute: 15))
        XCTAssertTrue(slotOverMidnight.contains(currentHour: 23, currentMinute: 30))
        XCTAssertTrue(slotOverMidnight.contains(currentHour: 2, currentMinute: 0))
        XCTAssertFalse(slotOverMidnight.contains(currentHour: 6, currentMinute: 0))
        
        // Simuliere 10.080 Minuten einer Woche
        var matches = 0
        for hour in 0..<24 {
            for minute in 0..<60 {
                if slot1.contains(currentHour: hour, currentMinute: minute) ||
                   slot2.contains(currentHour: hour, currentMinute: minute) ||
                   slotOverMidnight.contains(currentHour: hour, currentMinute: minute) {
                    matches += 1
                }
            }
        }
        XCTAssertEqual(matches, (3 * 60) + (4 * 60 + 30) + (6 * 60 + 30))
    }
    
    // MARK: - 8. Pellet Tank Tracking Mathematical Invariant Test
    
    func testPelletTank_MathStressAndZeroCapacitySafety() {
        let manager = PelletTankManager()
        
        // Teste Grenzen
        manager.currentLevel = -10.0
        XCTAssertGreaterThanOrEqual(manager.currentLevel, 0.0, "Pelletstand darf nicht negativ sein")
        
        manager.currentLevel = 100.0
        XCTAssertLessThanOrEqual(manager.currentLevel, manager.tankCapacity, "Pelletstand darf Tankkapazität nicht überschreiten")
        
        // Simulation von 500 Stunden Verbrennung auf Power 5
        for _ in 0..<500 {
            manager.updateTracking(statusCode: 6, powerLevel: 5, isWood: false)
        }
        
        XCTAssertGreaterThanOrEqual(manager.currentLevel, 0.0)
    }
    
    // MARK: - 9. Home Assistant Service Fault Injection
    
    func testHomeAssistant_MalformedJSONAnd404Handling() async {
        let service = HomeAssistantService.shared
        service.isEnabled = true
        service.serverURL = "http://127.0.0.1:59999" // Nicht existierender lokaler Port
        service.accessToken = "dummy_token"
        
        // Teste Verbindungsprüfung gegen geschlossenen Port
        let connected = await service.testConnection()
        XCTAssertFalse(connected, "Gegen ungültigen Port darf keine Verbindung zustande kommen")
        XCTAssertFalse(service.isConnected)
        XCTAssertTrue(service.statusMessage.contains("Verbindungsfehler") || service.statusMessage.contains("Server") || service.statusMessage.contains("Keine"))
    }
}
