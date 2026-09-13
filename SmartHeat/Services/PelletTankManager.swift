import Foundation
import Combine

/// Manages and calculates the pellet tank fill level, consumption, and burn-time forecast
/// tailored specifically for the Dielle Ghibli Kombi 10 kW (Pellet + Wood hybrid stove).
@MainActor
public class PelletTankManager: ObservableObject {
    // MARK: - Dielle Ghibli Kombi 10 kW Technical Specifications
    public static let defaultCapacity: Double = 20.0     // 20.0 kg maximum hopper capacity
    public static let defaultBagWeight: Double = 15.0    // 15.0 kg standard pellet bag
    public static let defaultIgnitionCost: Double = 0.20 // 200g pellet primer per ignition cycle
    
    /// Calibrated consumption rates in kg/h for Dielle Ghibli 10 kW per power level (P1 - P5)
    public static let ghibli10kWConsumptionRates: [Int: Double] = [
        1: 0.65, // P1 (Modulation / Teillast ca. 2.8 kW): 0.65 kg/h
        2: 0.95, // P2 (Niedrige Heizstufe ca. 4.5 kW):    0.95 kg/h
        3: 1.35, // P3 (Mittellast ca. 6.5 kW):           1.35 kg/h
        4: 1.80, // P4 (Hohe Heizstufe ca. 8.5 kW):       1.80 kg/h
        5: 2.25  // P5 (Volllast / Nennleistung 10.0 kW): 2.25 kg/h
    ]
    
    // MARK: - Published Properties
    @Published public var tankCapacity: Double {
        didSet { UserDefaults.standard.set(tankCapacity, forKey: "pellet_tank_capacity") }
    }
    
    @Published public var currentLevel: Double {
        didSet {
            let clamped = max(0.0, min(tankCapacity, currentLevel))
            if clamped != currentLevel { currentLevel = clamped }
            UserDefaults.standard.set(currentLevel, forKey: "pellet_current_level")
        }
    }
    
    @Published public var bagWeight: Double {
        didSet { UserDefaults.standard.set(bagWeight, forKey: "pellet_bag_weight") }
    }
    
    @Published public var isWoodModeActive: Bool = false
    @Published public var currentPowerLevel: Int = 1
    @Published public var lastRefillDate: Date? {
        didSet {
            if let date = lastRefillDate {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "pellet_last_refill")
            }
        }
    }
    
    private var lastTrackingDate: Date?
    private var previousStatus: Int = 0
    
    // MARK: - Initializer
    public init() {
        self.tankCapacity = UserDefaults.standard.object(forKey: "pellet_tank_capacity") as? Double ?? Self.defaultCapacity
        self.currentLevel = UserDefaults.standard.object(forKey: "pellet_current_level") as? Double ?? 18.0
        self.bagWeight = UserDefaults.standard.object(forKey: "pellet_bag_weight") as? Double ?? Self.defaultBagWeight
        
        if let savedRefill = UserDefaults.standard.object(forKey: "pellet_last_refill") as? Double {
            self.lastRefillDate = Date(timeIntervalSince1970: savedRefill)
        }
    }
    
    // MARK: - Computed Properties
    public var fillPercentage: Double {
        guard tankCapacity > 0 else { return 0 }
        return (currentLevel / tankCapacity) * 100.0
    }
    
    public var currentHourlyConsumption: Double {
        if isWoodModeActive { return 0.0 }
        return Self.ghibli10kWConsumptionRates[currentPowerLevel] ?? 1.00
    }
    
    public var remainingHours: Double {
        let rate = currentHourlyConsumption
        guard rate > 0 else { return 999.0 }
        return currentLevel / rate
    }
    
    public var isLowPellet: Bool {
        return fillPercentage <= 20.0
    }
    
    // MARK: - User Actions
    /// Adds one standard bag (15 kg) to the hopper, capped at tank capacity
    public func refillBag() {
        currentLevel = min(tankCapacity, currentLevel + bagWeight)
        lastRefillDate = Date()
    }
    
    /// Resets the tank to 100% capacity (20 kg)
    public func refillFull() {
        currentLevel = tankCapacity
        lastRefillDate = Date()
    }
    
    /// Manually sets the level to a specific kg amount (e.g. from slider)
    public func setLevel(kg: Double) {
        currentLevel = max(0.0, min(tankCapacity, kg))
    }
    
    // MARK: - Real-Time Consumption Tracking
    /// Called periodically upon receiving live telemetry from the stove
    public func updateTracking(statusCode: Int, powerLevel: Int, isWood: Bool) {
        let now = Date()
        self.isWoodModeActive = isWood
        self.currentPowerLevel = max(1, min(5, powerLevel))
        
        // Handle Ignition cycle: deduct primer pellet volume once upon switching from OFF/Standby to Ignition
        let isIgniting = (statusCode == 2 || statusCode == 4 || (30...34).contains(statusCode))
        let wasOffOrStandby = (previousStatus == 0 || previousStatus == 11)
        
        if wasOffOrStandby && isIgniting {
            currentLevel = max(0, currentLevel - Self.defaultIgnitionCost)
        }
        previousStatus = statusCode
        
        guard let last = lastTrackingDate else {
            lastTrackingDate = now
            return
        }
        
        let deltaSeconds = now.timeIntervalSince(last)
        lastTrackingDate = now
        
        // Only track active burning (Status 5 = Betrieb, 6 = Modulation), and pause when burning firewood
        if (statusCode == 5 || statusCode == 6) && !isWood && deltaSeconds > 0 && deltaSeconds < 3600 {
            let hourlyRate = Self.ghibli10kWConsumptionRates[self.currentPowerLevel] ?? 1.00
            let consumed = (hourlyRate / 3600.0) * deltaSeconds
            if consumed > 0 {
                currentLevel = max(0, currentLevel - consumed)
            }
        }
    }
}
