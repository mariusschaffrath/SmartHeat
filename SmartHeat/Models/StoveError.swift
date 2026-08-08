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
