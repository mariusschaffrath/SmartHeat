import Foundation

/// Represents a structured user-facing error with error codes and customer troubleshooting guidance
public struct StoveError: LocalizedError, Identifiable, Equatable {
    public var id: String { code }
    
    public let code: String
    public let title: String
    public let errorDescription: String?
    public let suggestion: String
    
    public init(code: String, title: String, description: String, suggestion: String) {
        self.code = code
        self.title = title
        self.errorDescription = description
        self.suggestion = suggestion
    }
    
    // Predefined Error Codes
    public static func loginFailed(message: String) -> StoveError {
        StoveError(
            code: "ERR-101",
            title: "Anmeldefehler (Cloud)",
            description: "Die Anmeldung am 4Heat Cloud-Server ist fehlgeschlagen: \(message)",
            suggestion: "Bitte überprüfe deine E-Mail-Adresse und dein Passwort in den Einstellungen."
        )
    }
    
    public static func cloudNetworkError(message: String) -> StoveError {
        StoveError(
            code: "ERR-102",
            title: "Keine Cloud-Verbindung",
            description: "Der 4Heat Server (wifi4heat.azurewebsites.net) ist nicht erreichbar. \(message)",
            suggestion: "Stelle sicher, dass dein Smartphone mit dem Internet verbunden ist und mobile Daten oder WLAN aktiv sind."
        )
    }
    
    public static func noDeviceFound() -> StoveError {
        StoveError(
            code: "ERR-103",
            title: "Kein Ofen gefunden",
            description: "Unter deinen Anmeldedaten konnte kein registrierter Dielle/4Heat Ofen gefunden werden.",
            suggestion: "Prüfe in den Einstellungen die Seriennummer oder verbinde den Ofen mit deinem Cloud-Konto."
        )
    }
    
    public static func socketConnectionFailed(host: String, detail: String) -> StoveError {
        StoveError(
            code: "ERR-201",
            title: "WLAN-Verbindung fehlgeschlagen",
            description: "Direktverbindung zum Ofen (\(host):80) fehlgeschlagen. \(detail)",
            suggestion: "Stelle sicher, dass du mit demselben WLAN-Netzwerk wie der Ofen verbunden bist und die IP-Adresse in den Einstellungen stimmt."
        )
    }
    
    public static func socketResponseTimeout() -> StoveError {
        StoveError(
            code: "ERR-202",
            title: "Keine Antwort vom Ofen",
            description: "Der Ofen reagiert nicht auf WLAN-Anfragen.",
            suggestion: "Trenne das WLAN-Modul des Ofens kurz vom Stromnetz und versuche es erneut."
        )
    }
    
    public static func commandFailed(command: String, detail: String) -> StoveError {
        StoveError(
            code: "ERR-301",
            title: "Schaltbefehl fehlgeschlagen",
            description: "Der Befehl '\(command)' konnte nicht an den Ofen gesendet werden. \(detail)",
            suggestion: "Prüfe, ob der Ofen mit dem WLAN verbunden und eingeschaltet ist."
        )
    }
    
    public static func sessionExpired() -> StoveError {
        StoveError(
            code: "ERR-302",
            title: "Sitzung abgelaufen",
            description: "Das Sicherheitstoken für den Cloud-Zugriff ist abgelaufen.",
            suggestion: "Bitte melde dich in den Einstellungen einmal ab und erneut an."
        )
    }
}

/// Represents a Dielle hardware alarm code reported directly by the TiEmme stove motherboard (Er01..Er42)
public struct DielleHardwareAlarm: Identifiable, Equatable {
    public let code: Int
    public let codeString: String
    public let title: String
    public let description: String
    public let remedy: String
    public var id: Int { code }
    
    public init(code: Int, codeString: String, title: String, description: String, remedy: String) {
        self.code = code
        self.codeString = codeString
        self.title = title
        self.description = description
        self.remedy = remedy
    }
    
    public static func from(code: Int) -> DielleHardwareAlarm? {
        guard code > 0 else { return nil }
        switch code {
        case 1:
            return DielleHardwareAlarm(
                code: 1,
                codeString: "Er01",
                title: "Überhitzungsthermostat Kessel/Wasser",
                description: "Überhitzung Wassertasche / Kesselkörper festgestellt.",
                remedy: "Abkühlung abwarten, Pumpe & Vorlauf prüfen. Tippe auf 'Entsperren', um den Alarm zu quittieren."
            )
        case 2:
            return DielleHardwareAlarm(
                code: 2,
                codeString: "Er02",
                title: "Sicherheitsdruckwächter Wasserdruck",
                description: "Druckfehler im Wasserkreislauf.",
                remedy: "Anlagendruck prüfen (Soll: 1.2–1.5 bar) und Alarm quittieren."
            )
        case 3:
            return DielleHardwareAlarm(
                code: 3,
                codeString: "Er03",
                title: "Erloschene Flamme / Pellets leer",
                description: "Keine Flamme im Heizbetrieb oder Pellettank leer.",
                remedy: "Pellets nachfüllen, Brenner kontrollieren und auf 'Entsperren' tippen."
            )
        case 4:
            return DielleHardwareAlarm(
                code: 4,
                codeString: "Er04",
                title: "Fehlzündung",
                description: "Temperaturanstieg bei Zündung zu gering.",
                remedy: "Brennraum reinigen, Glühkerze prüfen und Zündung erneut starten."
            )
        case 5:
            return DielleHardwareAlarm(
                code: 5,
                codeString: "Er05",
                title: "Rauchgastemperaturfühler defekt",
                description: "Rauchgastemperaturfühler defekt oder unterbrochen.",
                remedy: "Fühleranschluss an Platine sowie Verkabelung prüfen."
            )
        case 6:
            return DielleHardwareAlarm(
                code: 6,
                codeString: "Er06",
                title: "Temperaturfühler-Fehler",
                description: "Der Raum- oder Abgastemperaturfühler meldet einen Kurzschluss oder Kabelbruch.",
                remedy: "Fühlerverkabelung und Steckverbindung an der Ofenrückseite prüfen."
            )
        case 7:
            return DielleHardwareAlarm(
                code: 7,
                codeString: "Er07",
                title: "Abgasgebläse Drehzahlfehler",
                description: "Der Drehzahlgeber (Encoder) des Abgasventilators meldet eine Blockade oder Unregelmäßigkeit.",
                remedy: "Rauchgasventilator auf Verschmutzung oder mechanische Blockade prüfen."
            )
        case 8:
            return DielleHardwareAlarm(
                code: 8,
                codeString: "Er08",
                title: "Rauchgas-Übertemperatur",
                description: "Die Rauchgastemperatur hat den zulässigen Maximalwert überschritten.",
                remedy: "Ofen abkühlen lassen, Wärmetauscher und Kaminrohr auf Verrußung prüfen."
            )
        case 12:
            return DielleHardwareAlarm(
                code: 12,
                codeString: "Er12",
                title: "Pelletmangel / Dosierer",
                description: "Pelletförderung unzureichend oder Zündtopf nicht befüllt.",
                remedy: "Pelletbehälter prüfen, Pellets nachfüllen und Alarm quittieren."
            )
        case 39:
            return DielleHardwareAlarm(
                code: 39,
                codeString: "Er39",
                title: "Unterdruckwächter Brennraum / Kaminzug",
                description: "Schornsteinzug unzureichend oder Brennraumtür/Aschelade undicht.",
                remedy: "Brennraumtür schließen, Dichtungen und Schornsteinzug prüfen."
            )
        case 41:
            return DielleHardwareAlarm(
                code: 41,
                codeString: "Er41",
                title: "Luftstrom-Minimum unterschritten",
                description: "Verbrennungsluftstrom liegt unter dem Schwellwert.",
                remedy: "Luftansaugrohr und Gebläse auf Verstopfung prüfen."
            )
        case 42:
            return DielleHardwareAlarm(
                code: 42,
                codeString: "Er42",
                title: "Maximaler Luftstrom / Tür offen",
                description: "Luftstrom über Schwellwert oder Brennraumtür steht offen.",
                remedy: "Brennraumtür schließen und Sensor prüfen."
            )
        default:
            let codeFormatted = String(format: "Er%02d", code)
            return DielleHardwareAlarm(
                code: code,
                codeString: codeFormatted,
                title: "Störung \(codeFormatted)",
                description: "Die Ofenplatine meldet den Hardware-Alarmcode \(codeFormatted).",
                remedy: "Ofen überprüfen und auf 'Entsperren' tippen."
            )
        }
    }
}
