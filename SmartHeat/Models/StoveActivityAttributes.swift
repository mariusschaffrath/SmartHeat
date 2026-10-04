import Foundation
import ActivityKit

/// Attributes and dynamic state for Dielle Pellet/Hybrid Stove Live Activities
/// (Ignition countdown, Burnout / Cleaning phase, and Heating status).
nonisolated public struct StoveActivityAttributes: ActivityAttributes, Sendable {
    
    public struct ContentState: Codable, Hashable, Sendable {
        public var phaseName: String           // z.B. "Zündung Phase 1", "Zündung Phase 2", "Ausbrand", "Heizbetrieb"
        public var targetPhaseName: String     // z.B. "Heizbetrieb", "Aus / Abgekühlt"
        public var exhaustTemp: Double         // Abgastemperatur in °C
        public var roomTemp: Double            // Raumtemperatur in °C
        public var targetTemp: Double          // Solltemperatur in °C
        public var startDate: Date             // Startzeitpunkt der aktuellen Phase
        public var estimatedEndDate: Date      // Voraussichtliches Ende des Countdowns
        public var progress: Double            // 0.0 bis 1.0 Fortschritt der Phase
        public var isIgnition: Bool            // True = Zündungsphase (Flamme), False = Ausbrand/Reinigung
        public var isWoodActive: Bool          // True = Scheitholzbetrieb aktiv
        public var powerLevel: Int             // Aktuelle Leistungsstufe 1..5
        public var statusDetail: String        // z.B. "Glutbett bildet sich...", "Abgaskühlung aktiv..."
        
        public init(
            phaseName: String = "Zündung Phase 1",
            targetPhaseName: String = "Heizbetrieb",
            exhaustTemp: Double = 35.0,
            roomTemp: Double = 20.5,
            targetTemp: Double = 22.0,
            startDate: Date = Date(),
            estimatedEndDate: Date = Date().addingTimeInterval(720), // 12 Minuten Standard-Zündfenster
            progress: Double = 0.1,
            isIgnition: Bool = true,
            isWoodActive: Bool = false,
            powerLevel: Int = 3,
            statusDetail: String = "Pelletzufuhr & Heizelement aktiv"
        ) {
            self.phaseName = phaseName
            self.targetPhaseName = targetPhaseName
            self.exhaustTemp = exhaustTemp
            self.roomTemp = roomTemp
            self.targetTemp = targetTemp
            self.startDate = startDate
            self.estimatedEndDate = estimatedEndDate
            self.progress = progress
            self.isIgnition = isIgnition
            self.isWoodActive = isWoodActive
            self.powerLevel = powerLevel
            self.statusDetail = statusDetail
        }
    }
    
    // Feste Attribute beim Start
    public var stoveName: String
    public var stoveModel: String
    
    public init(
        stoveName: String = "Dielle Pelletofen",
        stoveModel: String = "Ghibli Hybrid 10 kW"
    ) {
        self.stoveName = stoveName
        self.stoveModel = stoveModel
    }
}
