//
//  WoodCombustionTracker.swift
//  SmartHeat
//
//  Dedicated hybrid combustion tracking for Dielle Ghibli Kombi 10 kW.
//  Monitors exhaust temperature curves during status 13 (Legna / Scheitholz)
//  and provides real-time refueling recommendations and pellet savings metrics.
//

import Foundation
import Combine

public enum WoodCombustionPhase: String, Codable {
    case idle = "Bereit"
    case igniting = "Anbrennen"
    case optimal = "Optimaler Holzbrand"
    case coalsRefillReady = "Glutbett (Nachlegen empfohlen)"
    case burnout = "Ausbrand / Pellet-Übernahme"
    
    public var icon: String {
        switch self {
        case .idle: return "leaf.fill"
        case .igniting: return "flame"
        case .optimal: return "flame.fill"
        case .coalsRefillReady: return "sparkles"
        case .burnout: return "smoke.fill"
        }
    }
    
    public var statusDescription: String {
        switch self {
        case .idle:
            return "Scheitholz kann eingelegt werden."
        case .igniting:
            return "Abgastemperatur steigt rasch an. Kaminzug stabilisiert sich."
        case .optimal:
            return "Perfekte Verbrennung bei 190°C–320°C. Höchster Wirkungsgrad, null Ruß."
        case .coalsRefillReady:
            return "Ideales Glutbett vorhanden! Jetzt neues Holzscheit ohne Neuzündung auflegen."
        case .burnout:
            return "Glut erlischt. Ofen übernimmt bei weiterem Wärmebedarf automatisch die Pelletzündung."
        }
    }
}

@MainActor
public class WoodCombustionTracker: ObservableObject {
    public static let shared = WoodCombustionTracker()
    
    @Published public var currentPhase: WoodCombustionPhase = .idle
    @Published public var isWoodActive: Bool = false
    @Published public var currentWoodSessionDuration: TimeInterval = 0
    @Published public var sessionSavedPelletsKg: Double = 0.0
    @Published public var lifetimeSavedPelletsKg: Double
    
    private var sessionStartDate: Date?
    private let lifetimeKey = "wood_lifetime_saved_pellets_kg"
    
    public init() {
        self.lifetimeSavedPelletsKg = UserDefaults.standard.double(forKey: lifetimeKey)
    }
    
    /// Update tracking state based on current stove status and exhaust temperature
    public func update(statusCode: Int, exhaustTemp: Double) {
        let isNowWood = (statusCode == 13)
        
        if isNowWood {
            if !isWoodActive {
                // Session started
                isWoodActive = true
                sessionStartDate = Date()
                currentWoodSessionDuration = 0
            } else if let start = sessionStartDate {
                currentWoodSessionDuration = Date().timeIntervalSince(start)
                // 1.35 kg/h saved pellet equivalent
                let hours = currentWoodSessionDuration / 3600.0
                let saved = hours * 1.35
                sessionSavedPelletsKg = round(saved * 100.0) / 100.0
            }
            
            // Determine Combustion Phase from exhaust temperature curve
            if exhaustTemp >= 190.0 && exhaustTemp <= 320.0 {
                currentPhase = .optimal
            } else if exhaustTemp >= 130.0 && exhaustTemp < 190.0 {
                currentPhase = .coalsRefillReady
            } else if exhaustTemp > 100.0 && exhaustTemp < 130.0 {
                currentPhase = .burnout
            } else if exhaustTemp > 60.0 {
                currentPhase = .igniting
            } else {
                currentPhase = .idle
            }
        } else {
            if isWoodActive {
                // Session ended
                isWoodActive = false
                currentPhase = .idle
                lifetimeSavedPelletsKg += sessionSavedPelletsKg
                UserDefaults.standard.set(lifetimeSavedPelletsKg, forKey: lifetimeKey)
                sessionStartDate = nil
            }
        }
    }
}
