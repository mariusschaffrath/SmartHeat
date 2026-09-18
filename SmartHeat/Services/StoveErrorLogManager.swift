//
//  StoveErrorLogManager.swift
//  SmartHeat
//
//  Decodes Dielle hardware error registers (Er01..Er15), stores timestamped logs,
//  and provides troubleshooting guidance for Marius.
//

import Foundation
import SwiftUI
import Combine

public enum ErrorSeverity: String, Codable {
    case critical = "Kritisch"
    case warning = "Warnung"
    case info = "Hinweis"
    
    public var color: Color {
        switch self {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
    
    public var icon: String {
        switch self {
        case .critical: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

public struct StoveErrorLogEntry: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let code: String
    public let title: String
    public let detail: String
    public let solution: String
    public let severity: ErrorSeverity
    public var isResolved: Bool
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        code: String,
        title: String,
        detail: String,
        solution: String,
        severity: ErrorSeverity = .warning,
        isResolved: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.code = code
        self.title = title
        self.detail = detail
        self.solution = solution
        self.severity = severity
        self.isResolved = isResolved
    }
}

@MainActor
public class StoveErrorLogManager: ObservableObject {
    public static let shared = StoveErrorLogManager()
    
    private let storageKey = "smartheat_stove_error_history"
    
    @Published public var errorLog: [StoveErrorLogEntry] = []
    
    public var unresolvedCount: Int {
        errorLog.filter { !$0.isResolved }.count
    }
    
    // MARK: - Known Dielle / SyEvo Fault Registry
    public static let knownFaults: [String: (title: String, detail: String, solution: String, severity: ErrorSeverity)] = [
        "Er01": (
            title: "Keine Zündung / Pellet-Mangel",
            detail: "Die Flamme konnte während der Zündphase nicht rechtzeitig gezündet werden.",
            solution: "Brennertopf auf Verkrustungen prüfen, reinigen und sicherstellen, dass Pellets im Trichter nachrutschen.",
            severity: .warning
        ),
        "Er02": (
            title: "Sicherheitsthermostat ausgelöst",
            detail: "Kessel- oder Gehäusetemperatur hat die Abschaltschwelle (ca. 95°C) überschritten.",
            solution: "Ofen vollständig abkühlen lassen. Mechanischen Thermostat-Rückstellknopf an der Rückseite prüfen.",
            severity: .critical
        ),
        "Er03": (
            title: "Abgastemperatur überschritten",
            detail: "Die Rauchgastemperatur ist über den zulässigen Maximalwert (ca. 260°C) gestiegen.",
            solution: "Wärmetauscherrohre mit Rüttelgestänge abreinigen und Leistungsstufe für den Raum drosseln.",
            severity: .critical
        ),
        "Er04": (
            title: "Rauchgassensor defekt",
            detail: "Der Abgas-Thermokoppler liefert unplausible Werte oder ist unterbrochen.",
            solution: "Sensor-Steckverbindung am Rauchgasausgang prüfen oder Fühler austauschen lassen.",
            severity: .critical
        ),
        "Er05": (
            title: "Druckwächter ausgelöst / Tür offen",
            detail: "Der Unterdruck in der Brennkammer ist unzureichend oder die Brennraumtür steht offen.",
            solution: "Brennraumtür fest verriegeln, Dichtungsgummi kontrollieren und Kaminrohr auf Durchzug prüfen.",
            severity: .critical
        ),
        "Er07": (
            title: "Rauchgasgebläse Drehzahlfehler",
            detail: "Das Tachosignal des Abgasgebläses wurde unterbrochen oder Lüfter ist blockiert.",
            solution: "Rauchgasventilator auf Rußablagerungen oder mechanischen Widerstand kontrollieren.",
            severity: .critical
        ),
        "Er08": (
            title: "Pellettank-Temperatursensor",
            detail: "Erhöhte Temperatur im Pelletvorratsbereich registriert (Rückbrandsicherung).",
            solution: "Ofen sofort abkühlen lassen, Förderschacht auf Verstopfung prüfen.",
            severity: .critical
        ),
        "Er11": (
            title: "Zündverzögerung",
            detail: "Zündelement hat zu lange benötigt, um die notwendige Mindesttemperatur zu erreichen.",
            solution: "Glühkerze auf Verschleiß prüfen und trockene DINplus-Pellets verwenden.",
            severity: .warning
        ),
        "Er12": (
            title: "Flamme im Heizbetrieb erloschen",
            detail: "Die Abgastemperatur ist während des laufenden Heizbetriebs unerwartet abgefallen.",
            solution: "Pelletvorrat auffüllen und Förderschnecke auf Leerlauf kontrollieren.",
            severity: .warning
        ),
        "Er15": (
            title: "Netzausfall während des Betriebs",
            detail: "Stromversorgung wurde während des Verbrennungsvorgangs unterbrochen.",
            solution: "Nach Stromwiederkehr führt der Ofen eine Sicherheitsabkühlung durch. Ggf. danach neu starten.",
            severity: .info
        )
    ]
    
    public init() {
        loadHistory()
        seedInitialHistoryIfNeeded()
    }
    
    public func logError(code: String, customDetail: String? = nil) {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Don't duplicate if already logged within last 10 minutes
        if let first = errorLog.first, first.code == cleanCode && abs(first.timestamp.timeIntervalSinceNow) < 600 {
            return
        }
        
        let fault = Self.knownFaults[cleanCode] ?? (
            title: "Störung (\(cleanCode))",
            detail: customDetail ?? "Vom Ofen wurde ein Systemfehler übermittelt.",
            solution: "Ofen ausschalten, Strom trennen und Brennraum kontrollieren.",
            severity: .warning
        )
        
        let entry = StoveErrorLogEntry(
            code: cleanCode,
            title: fault.title,
            detail: customDetail ?? fault.detail,
            solution: fault.solution,
            severity: fault.severity,
            isResolved: false
        )
        
        errorLog.insert(entry, at: 0)
        saveHistory()
        
        // Trigger notification
        NotificationManager.shared.checkStoveError(
            errorCode: cleanCode,
            errorTitle: fault.title,
            solution: fault.solution
        )
    }
    
    public func markResolved(id: UUID) {
        if let idx = errorLog.firstIndex(where: { $0.id == id }) {
            errorLog[idx].isResolved = true
            saveHistory()
        }
    }
    
    public func resolveAll() {
        for idx in errorLog.indices {
            errorLog[idx].isResolved = true
        }
        saveHistory()
    }
    
    public func clearHistory() {
        errorLog.removeAll()
        saveHistory()
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(errorLog) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let list = try? JSONDecoder().decode([StoveErrorLogEntry].self, from: data) {
            self.errorLog = list
        }
    }
    
    private func seedInitialHistoryIfNeeded() {
        guard errorLog.isEmpty else { return }
        let calendar = Calendar.current
        let pastDate = calendar.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        
        let sample = StoveErrorLogEntry(
            id: UUID(),
            timestamp: pastDate,
            code: "Er12",
            title: "Flamme im Heizbetrieb erloschen",
            detail: "Pelletvorrat war vollständig erschöpft. Ofen ging automatisch in Ausbrand.",
            solution: "Pellettank befüllt und Ofen neu gestartet.",
            severity: .warning,
            isResolved: true
        )
        errorLog.append(sample)
        saveHistory()
    }
}
