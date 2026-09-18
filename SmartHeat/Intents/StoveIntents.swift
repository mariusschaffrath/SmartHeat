//
//  StoveIntents.swift
//  SmartHeat
//
//  Native Apple Siri & Shortcuts Integration via AppIntents
//  Supports natural language Siri commands:
//  - "Setze Zieltemperatur des Ofens auf 22 Grad"
//  - "Gebläse im Flur auf Stufe 3"
//  - "Schalte den Ofen ein / aus"
//  - "Wie ist der Status des Ofens?"
//

import AppIntents
import Foundation

// MARK: - AppEnums for Siri Phrases
public enum TargetTemperatureChoice: Double, AppEnum {
    case t16 = 16.0
    case t17 = 17.0
    case t18 = 18.0
    case t18_5 = 18.5
    case t19 = 19.0
    case t19_5 = 19.5
    case t20 = 20.0
    case t20_5 = 20.5
    case t21 = 21.0
    case t21_5 = 21.5
    case t22 = 22.0
    case t22_5 = 22.5
    case t23 = 23.0
    case t23_5 = 23.5
    case t24 = 24.0
    case t25 = 25.0
    case t26 = 26.0
    
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Zieltemperatur"
    
    public static var caseDisplayRepresentations: [TargetTemperatureChoice: DisplayRepresentation] = [
        .t16: "16 Grad",
        .t17: "17 Grad",
        .t18: "18 Grad",
        .t18_5: "18,5 Grad",
        .t19: "19 Grad",
        .t19_5: "19,5 Grad",
        .t20: "20 Grad",
        .t20_5: "20,5 Grad",
        .t21: "21 Grad",
        .t21_5: "21,5 Grad",
        .t22: "22 Grad",
        .t22_5: "22,5 Grad",
        .t23: "23 Grad",
        .t23_5: "23,5 Grad",
        .t24: "24 Grad",
        .t25: "25 Grad",
        .t26: "26 Grad"
    ]
}

public enum FanSpeedChoice: Int, AppEnum {
    case off = 0
    case p1 = 1
    case p2 = 2
    case p3 = 3
    case p4 = 4
    case p5 = 5
    case auto = 6
    
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Gebläsestufe"
    
    public static var caseDisplayRepresentations: [FanSpeedChoice: DisplayRepresentation] = [
        .off: "Aus",
        .p1: "Stufe 1",
        .p2: "Stufe 2",
        .p3: "Stufe 3",
        .p4: "Stufe 4",
        .p5: "Stufe 5",
        .auto: "Auto"
    ]
}

// MARK: - Helper to retrieve Cloud Credentials
private enum StoveIntentHelper {
    static func getCredentials() -> (token: String, deviceKey: String)? {
        let token = UserDefaults.standard.string(forKey: "cloud_token") ?? KeychainService.shared.load(key: "cloud_token")
        guard let validToken = token, !validToken.isEmpty else { return nil }
        let deviceKey = UserDefaults.standard.string(forKey: "saved_device_id") ?? "25016460"
        return (validToken, deviceKey)
    }
}

// MARK: - 1. Setze Zieltemperatur des Ofens
public struct SetStoveTemperatureIntent: AppIntent {
    public static var title: LocalizedStringResource = "Zieltemperatur einstellen"
    public static var description = IntentDescription("Stellt die gewünschte Zieltemperatur für den Pelletofen ein.")
    public static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Temperatur", description: "Die gewünschte Zieltemperatur (z.B. 21, 22 oder 23 Grad)")
    public var temperature: TargetTemperatureChoice
    
    public init() {
        self.temperature = .t21
    }
    public init(temperature: TargetTemperatureChoice) {
        self.temperature = temperature
    }
    
    public static var parameterSummary: some ParameterSummary {
        Summary("Setze Zieltemperatur auf \(\.$temperature)")
    }
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let (token, deviceKey) = StoveIntentHelper.getCredentials() else {
            return .result(dialog: "Du bist in SmartHeat noch nicht angemeldet. Bitte öffne die App kurz zum Anmelden.")
        }
        
        let targetValue = temperature.rawValue
        let cmd = StoveCommand.writeParameter(value: Int(targetValue * 10))
        
        do {
            try await CloudService.shared.sendCommand(deviceKey: deviceKey, token: token, command: cmd)
            return .result(dialog: "Zieltemperatur des Ofens auf \(String(format: "%.1f", targetValue)) Grad gestellt.")
        } catch {
            return .result(dialog: "Befehl konnte nicht gesendet werden: \(error.localizedDescription)")
        }
    }
}

// MARK: - 2. Gebläse im Flur auf Stufe X
public struct SetFlurFanSpeedIntent: AppIntent {
    public static var title: LocalizedStringResource = "Flur-Gebläse einstellen"
    public static var description = IntentDescription("Stellt das Kanalgebläse im Flur auf Aus, Stufe 1 bis 5 oder Auto.")
    public static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Gebläsestufe", description: "Aus, Stufe 1 bis 5 oder Auto")
    public var speed: FanSpeedChoice
    
    public init() {
        self.speed = .p1
    }
    public init(speed: FanSpeedChoice) {
        self.speed = speed
    }
    
    public static var parameterSummary: some ParameterSummary {
        Summary("Setze Gebläse im Flur auf \(\.$speed)")
    }
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let (token, deviceKey) = StoveIntentHelper.getCredentials() else {
            return .result(dialog: "Du bist in SmartHeat noch nicht angemeldet. Bitte öffne die App kurz.")
        }
        
        let speedVal = speed.rawValue
        // Kanal 1 (Flur) ist Register 027e
        let cmd = StoveCommand.writeParameter(id: "027e", value: speedVal)
        
        do {
            try await CloudService.shared.sendCommand(deviceKey: deviceKey, token: token, command: cmd)
            let speedLabel = speedVal == 0 ? "Aus" : (speedVal == 6 ? "Auto" : "Stufe \(speedVal)")
            return .result(dialog: "Das Gebläse im Flur steht jetzt auf \(speedLabel).")
        } catch {
            return .result(dialog: "Kanalgebläse konnte nicht verstellt werden: \(error.localizedDescription)")
        }
    }
}

// MARK: - 3. Ofen Einschalten
public struct TurnOnStoveIntent: AppIntent {
    public static var title: LocalizedStringResource = "Pelletofen einschalten"
    public static var description = IntentDescription("Startet die Zündung des Pelletofens.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let (token, deviceKey) = StoveIntentHelper.getCredentials() else {
            return .result(dialog: "Bitte öffne die SmartHeat App zum Anmelden.")
        }
        
        do {
            try await CloudService.shared.sendCommand(deviceKey: deviceKey, token: token, command: .turnOn)
            return .result(dialog: "Der Pelletofen wurde eingeschaltet und zündet jetzt.")
        } catch {
            return .result(dialog: "Ofen konnte nicht eingeschaltet werden: \(error.localizedDescription)")
        }
    }
}

// MARK: - 4. Ofen Ausschalten
public struct TurnOffStoveIntent: AppIntent {
    public static var title: LocalizedStringResource = "Pelletofen ausschalten"
    public static var description = IntentDescription("Schaltet den Pelletofen aus.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let (token, deviceKey) = StoveIntentHelper.getCredentials() else {
            return .result(dialog: "Bitte öffne die SmartHeat App zum Anmelden.")
        }
        
        do {
            try await CloudService.shared.sendCommand(deviceKey: deviceKey, token: token, command: .turnOff)
            return .result(dialog: "Der Pelletofen schaltet jetzt aus.")
        } catch {
            return .result(dialog: "Ofen konnte nicht ausgeschaltet werden: \(error.localizedDescription)")
        }
    }
}

// MARK: - 5. Ofenstatus abfragen
public struct GetStoveStatusIntent: AppIntent {
    public static var title: LocalizedStringResource = "Ofenstatus abfragen"
    public static var description = IntentDescription("Liest Raumtemperatur, Abgastemperatur und Zustand des Ofens vor.")
    public static var openAppWhenRun: Bool = false
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let (token, deviceKey) = StoveIntentHelper.getCredentials() else {
            return .result(dialog: "Bitte melde dich in SmartHeat an.")
        }
        
        do {
            if let data = try await CloudService.shared.fetchStoveUpdate(deviceKey: deviceKey, token: token),
               let mapped = data.getMappedValues() {
                let statusWord: String
                switch mapped.status {
                case 0: statusWord = "ausgeschaltet"
                case 1, 2, 3, 4, 10: statusWord = "am Zünden"
                case 5: statusWord = "in Betrieb"
                case 11: statusWord = "im Standby"
                case 6: statusWord = "in der Modulation"
                default: statusWord = "eingeschaltet"
                }
                
                let answer = "Der Ofen ist \(statusWord). Raumtemperatur beträgt \(String(format: "%.1f", mapped.room)) Grad, Abgastemperatur \(String(format: "%.0f", mapped.exhaust)) Grad bei Zieltemperatur \(String(format: "%.1f", mapped.target)) Grad."
                return .result(dialog: "\(answer)")
            }
            return .result(dialog: "Keine Live-Telemetrie vom Ofen empfangen.")
        } catch {
            return .result(dialog: "Fehler beim Abrufen: \(error.localizedDescription)")
        }
    }
}

// MARK: - Native Siri Shortcuts Provider
public struct SmartHeatShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetStoveTemperatureIntent(),
            phrases: [
                "Setze Zieltemperatur des \(.applicationName) auf \(\.$temperature)",
                "Setze Zieltemperatur auf \(\.$temperature) mit \(.applicationName)",
                "Stelle \(.applicationName) auf \(\.$temperature)",
                "Heize mit \(.applicationName) auf \(\.$temperature)"
            ],
            shortTitle: "Zieltemperatur setzen",
            systemImageName: "thermometer.medium"
        )
        AppShortcut(
            intent: SetFlurFanSpeedIntent(),
            phrases: [
                "Gebläse im Flur mit \(.applicationName) auf \(\.$speed)",
                "Flur-Gebläse mit \(.applicationName) auf \(\.$speed)"
            ],
            shortTitle: "Flur-Gebläse steuern",
            systemImageName: "wind"
        )
        AppShortcut(
            intent: TurnOnStoveIntent(),
            phrases: [
                "Schalte den \(.applicationName) ein",
                "Schalte den Ofen ein mit \(.applicationName)"
            ],
            shortTitle: "Ofen einschalten",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: TurnOffStoveIntent(),
            phrases: [
                "Schalte den \(.applicationName) aus",
                "Schalte den Ofen aus mit \(.applicationName)"
            ],
            shortTitle: "Ofen ausschalten",
            systemImageName: "power"
        )
        AppShortcut(
            intent: GetStoveStatusIntent(),
            phrases: [
                "Wie ist der Status von \(.applicationName)?",
                "Wie warm ist es im \(.applicationName)?",
                "Ofenstatus abfragen mit \(.applicationName)"
            ],
            shortTitle: "Ofenstatus abfragen",
            systemImageName: "info.circle"
        )
    }
}
