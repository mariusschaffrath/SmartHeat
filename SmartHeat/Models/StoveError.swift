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
                title: "Stromausfall (Blackout)",
                description: "Während des Betriebs ist der Netzstrom kurzzeitig ausgefallen.",
                remedy: "Prüfe Stromanschluss und Sicherung. Tippe auf 'Entsperren', um den Alarm zu quittieren."
            )
        case 2:
            return DielleHardwareAlarm(
                code: 2,
                codeString: "Er02",
                title: "Fehlzündung (Keine Zündung)",
                description: "Die Zündphase wurde abgebrochen, da die Mindest-Abgastemperatur nicht rechtzeitig erreicht wurde.",
                remedy: "1. Brennertopf reinigen.\n2. Pelletzufuhr prüfen.\n3. Auf 'Entsperren' tippen und Zündung erneut starten."
            )
        case 3:
            return DielleHardwareAlarm(
                code: 3,
                codeString: "Er03",
                title: "Pellets leer / Flamme erloschen",
                description: "Der Brennertopf erhält keine Pellets mehr oder die Flamme ist im Heizbetrieb erloschen.",
                remedy: "1. Pelletbehälter auffüllen.\n2. Förderschnecke prüfen.\n3. Auf 'Entsperren' tippen."
            )
        case 4:
            return DielleHardwareAlarm(
                code: 4,
                codeString: "Er04",
                title: "Sicherheitsthermostat ausgelöst",
                description: "Die Temperatur im Pelletbehälter oder Gehäuse hat den Maximalwert überschritten.",
                remedy: "Ofen abkühlen lassen. Lüftungsschlitze frei halten. Gegebenenfalls thermischen Sicherheitsschalter prüfen."
            )
        case 5:
            return DielleHardwareAlarm(
                code: 5,
                codeString: "Er05",
                title: "Abgastemperatur zu hoch",
                description: "Die Abgastemperatur hat den zulässigen Grenzwert überschritten.",
                remedy: "Lass den Ofen abkühlen. Prüfe Wärmetauscher und Kaminrohr auf Verrußung."
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
        case 12:
            return DielleHardwareAlarm(
                code: 12,
                codeString: "Er12",
                title: "Pelletmangel / Dosierer",
                description: "Die Pelletförderung konnte den Brennertopf nicht ausreichend befüllen.",
                remedy: "Pellets nachfüllen und Alarm quittieren."
            )
        case 39:
            return DielleHardwareAlarm(
                code: 39,
                codeString: "Er39",
                title: "Unterdruckwächter ausgelöst",
                description: "Der Druckwächter meldet unzureichenden Schornsteinzug oder eine geöffnete Tür.",
                remedy: "1. Brennraumtür und Aschelade fest verschließen.\n2. Dichtungen und Kaminabzug prüfen.\n3. Auf 'Entsperren' tippen."
            )
        case 41:
            return DielleHardwareAlarm(
                code: 41,
                codeString: "Er41",
                title: "Luftstrom-Minimum unterschritten",
                description: "Die Verbrennungsluftzufuhr ist unzureichend.",
                remedy: "Lufteinlass auf Verstopfung prüfen."
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
