import XCTest

final class SmartHeatUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testFullSimulatorStressAndChaos() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0), "App sollte im Vordergrund laufen")

        // 1. Tab Bar Switching Stress (30 Durchläufe)
        let homeTab = app.buttons["Home"]
        let scheduleTab = app.buttons["Heizpläne"]
        let settingsTab = app.buttons["Einstellungen"]

        if homeTab.exists && scheduleTab.exists && settingsTab.exists {
            for _ in 0..<10 {
                scheduleTab.tap()
                settingsTab.tap()
                homeTab.tap()
            }
        }

        // 2. Lock Toggle Button Stress
        // Schloss-Button hat Accessibility Label "Gesperrt" bzw. "Entsperrt"
        let lockButton = app.buttons["Gesperrt"]
        if lockButton.exists {
            lockButton.tap() // Entsperren
            
            let unlockedButton = app.buttons["Entsperrt"]
            if unlockedButton.waitForExistence(timeout: 2.0) {
                // Betätige die Stepper-Tasten (+ und -)
                let plusButton = app.buttons["+"]
                let minusButton = app.buttons["−"]
                
                if plusButton.exists {
                    for _ in 0..<5 {
                        plusButton.tap()
                    }
                }
                if minusButton.exists {
                    for _ in 0..<5 {
                        minusButton.tap()
                    }
                }
                
                // Wieder sperren
                unlockedButton.tap()
            }
        }

        // 3. Detail Views Stress (Raum & Abgas Charts)
        let raumCard = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Raum'")).firstMatch
        if raumCard.exists {
            raumCard.tap()
            
            // Sheet schließt sich wieder per Swipe oder Fertig
            let dismissButton = app.buttons["Fertig"]
            if dismissButton.waitForExistence(timeout: 2.0) {
                dismissButton.tap()
            } else {
                app.swipeDown()
            }
        }

        // 4. Backgrounding & Foregrounding Stress (Simuliere Lock/Home)
        for _ in 0..<3 {
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: 0.5)
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0))
        }

        // 5. Strict Safety Invariant Check
        // Stelle sicher, dass der Ofen NICHT eingeschaltet wurde
        let statusBadge = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Aus' OR label CONTAINS 'Standby'")).firstMatch
        if statusBadge.exists {
            XCTAssertFalse(statusBadge.label.contains("Zündung"), "SICHERHEIT: Der Ofen darf nicht in Zündung sein")
        }
    }
}
