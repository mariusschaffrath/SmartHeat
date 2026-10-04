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
            return "Bereit für Hybridbetrieb. Scheitholz kann eingelegt werden."
        case .igniting:
            return "Scheitholzentzündung erkannt. Hybrid-Automatik stoppt Pelletförderung."
        case .optimal:
            return "Optimaler Holzbrand bei 190°C–320°C. Höchster Wirkungsgrad, null Pelletverbrauch."
        case .coalsRefillReady:
            return "Ideales Glutbett vorhanden! Jetzt neues Holzscheit auflegen, um automatischen Pelletstart zu vermeiden."
        case .burnout:
            return "Glutbett erlischt. Hybrid-Automatik: Ofen übernimmt bei weiterem Wärmebedarf nahtlos die Pelletzündung."
        }
    }
}

@MainActor
public class WoodCombustionTracker: ObservableObject {
    public static let shared = WoodCombustionTracker()
    
    @Published public var currentPhase: WoodCombustionPhase = .idle
    @Published public var isWoodActive: Bool = false
    @Published public var currentWoodSessionDuration: TimeInterval = 0
    @Published public var effectiveCombustionDuration: TimeInterval = 0
    @Published public var sessionSavedPelletsKg: Double = 0.0
    @Published public var lifetimeSavedPelletsKg: Double
    
    // Directional Tracking & Peak Memory (Hürde 4.1)
    @Published public private(set) var tempGradient: Double = 0.0 // °C / minute
    @Published public private(set) var sessionPeakExhaustTemp: Double = 0.0
    
    private var sessionStartDate: Date?
    private var lastTempUpdateDate: Date?
    private var lastExhaustTemp: Double?
    private let lifetimeKey = "wood_lifetime_saved_pellets_kg"
    
    public init() {
        self.lifetimeSavedPelletsKg = UserDefaults.standard.double(forKey: lifetimeKey)
    }
    
    nonisolated deinit {}
    
    public func resetSession() {
        isWoodActive = false
        currentPhase = .idle
        currentWoodSessionDuration = 0
        effectiveCombustionDuration = 0
        sessionSavedPelletsKg = 0.0
        sessionPeakExhaustTemp = 0.0
        tempGradient = 0.0
        sessionStartDate = nil
        lastTempUpdateDate = nil
        lastExhaustTemp = nil
    }
    
    /// Update tracking state based on current stove status and exhaust temperature (Hürde 4.1 & 4.2)
    public func update(statusCode: Int, exhaustTemp: Double, timestamp: Date = Date()) {
        let isNowWood = (statusCode == 13)
        
        if isNowWood {
            if !isWoodActive {
                // Session started
                isWoodActive = true
                sessionStartDate = timestamp
                lastTempUpdateDate = timestamp
                lastExhaustTemp = exhaustTemp
                currentWoodSessionDuration = 0
                effectiveCombustionDuration = 0
                sessionSavedPelletsKg = 0.0
                sessionPeakExhaustTemp = exhaustTemp
                tempGradient = 0.0
            } else {
                let now = timestamp
                if let start = sessionStartDate {
                    currentWoodSessionDuration = max(0, now.timeIntervalSince(start))
                }
                
                // Calculate temperature gradient (dT/dt in °C/min)
                var dt: TimeInterval = 0
                if let lastTemp = lastExhaustTemp, let lastDate = lastTempUpdateDate {
                    dt = now.timeIntervalSince(lastDate)
                    if dt > 0.05 {
                        tempGradient = ((exhaustTemp - lastTemp) / dt) * 60.0
                        lastExhaustTemp = exhaustTemp
                        lastTempUpdateDate = now
                    }
                } else {
                    lastExhaustTemp = exhaustTemp
                    lastTempUpdateDate = now
                    tempGradient = 0.0
                }
                
                // Track peak temperature
                if exhaustTemp > sessionPeakExhaustTemp {
                    sessionPeakExhaustTemp = exhaustTemp
                }
                
                // Hürde 4.2: Guard against phantom pellet savings on cold stove (< 100°C)
                if exhaustTemp >= 100.0 && dt > 0 {
                    effectiveCombustionDuration += dt
                    let hours = effectiveCombustionDuration / 3600.0
                    let saved = hours * 1.35 // 1.35 kg/h saved pellet equivalent for Ghibli Kombi 10 kW
                    sessionSavedPelletsKg = round(saved * 100.0) / 100.0
                }
            }
            
            // Hürde 4.1: Determine Combustion Phase with directional dT/dt & Peak logic
            if exhaustTemp < 60.0 {
                currentPhase = .idle
            } else if exhaustTemp >= 180.0 {
                currentPhase = .optimal
            } else if sessionPeakExhaustTemp >= 180.0 && (tempGradient <= 0.5 || exhaustTemp < sessionPeakExhaustTemp - 10.0) {
                // Peak was established and temperature is falling or holding at coals
                if exhaustTemp >= 120.0 {
                    currentPhase = .coalsRefillReady
                } else {
                    currentPhase = .burnout
                }
            } else {
                // Rising towards peak or initial heat-up (< 180°C)
                currentPhase = .igniting
            }
        } else {
            if isWoodActive {
                // Session ended
                isWoodActive = false
                currentPhase = .idle
                lifetimeSavedPelletsKg += sessionSavedPelletsKg
                UserDefaults.standard.set(lifetimeSavedPelletsKg, forKey: lifetimeKey)
                sessionStartDate = nil
                lastTempUpdateDate = nil
                lastExhaustTemp = nil
                tempGradient = 0.0
                sessionPeakExhaustTemp = 0.0
            }
        }
    }
}
