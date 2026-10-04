import Foundation
import ActivityKit
import SwiftUI
import Combine

/// Manager responsible for starting, updating, and dismissing ActivityKit Live Activities
/// and Dynamic Island presentations for Dielle pellet stove ignition and burnout phases.
@MainActor
public final class StoveLiveActivityManager: ObservableObject {
    public static let shared = StoveLiveActivityManager()
    
    @Published public private(set) var activeActivityId: String?
    @Published public private(set) var currentContentState: StoveActivityAttributes.ContentState?
    @Published public private(set) var currentPhase: String?
    
    private var currentActivity: Activity<StoveActivityAttributes>?
    private var phaseStartDate: Date?
    private var estimatedEndDate: Date?
    
    // Expected default durations (in seconds)
    public static let defaultIgnitionDuration: TimeInterval = 12 * 60 // 12 Minuten
    public static let defaultBurnoutDuration: TimeInterval = 20 * 60  // 20 Minuten
    
    private init() {}
    
    /// Checks whether Live Activities are enabled by the user in iOS Settings.
    public var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }
    
    // MARK: - Central State Synchronizer
    
    /// Evaluates stove telemetry and automatically activates, updates, or dismisses Live Activities.
    public func syncWithStove(
        operationalState: StoveOperationalState,
        stoveStatus: String,
        exhaustTemp: Double,
        roomTemp: Double,
        targetTemp: Double,
        powerLevel: Int,
        isWoodActive: Bool
    ) {
        guard areActivitiesEnabled else { return }
        
        switch operationalState {
        case .igniting:
            // Zündungsphase aktiv
            startOrUpdateIgnition(
                phaseName: stoveStatus,
                exhaustTemp: exhaustTemp,
                roomTemp: roomTemp,
                targetTemp: targetTemp,
                powerLevel: powerLevel,
                isWoodActive: isWoodActive
            )
            
        case .off:
            // Prüfen, ob Ausbrand oder Reinigung aktiv ist
            let isBurnout = stoveStatus.localizedCaseInsensitiveContains("Ausbrand") ||
                            stoveStatus.localizedCaseInsensitiveContains("Reinigung") ||
                            stoveStatus.localizedCaseInsensitiveContains("Ascheentleerung")
            
            if isBurnout || exhaustTemp > 55.0 {
                startOrUpdateBurnout(
                    phaseName: isBurnout ? stoveStatus : "Ausbrand / Abkühlung",
                    exhaustTemp: exhaustTemp,
                    roomTemp: roomTemp,
                    targetTemp: targetTemp
                )
            } else {
                // Ofen ist kalt und vollständig aus -> Live Activity beenden
                if currentActivity != nil {
                    endLiveActivity(dismissalPolicy: .immediate)
                }
            }
            
        case .on:
            // Ofen ist im regulären Heizbetrieb
            if let activity = currentActivity, currentContentState?.isIgnition == true {
                // Zündung war aktiv -> Erfolgsmeldung anzeigen und nach 1 Minute ausblenden
                let completedState = StoveActivityAttributes.ContentState(
                    phaseName: "Flamme stabil",
                    targetPhaseName: "Heizbetrieb",
                    exhaustTemp: exhaustTemp,
                    roomTemp: roomTemp,
                    targetTemp: targetTemp,
                    startDate: phaseStartDate ?? Date(),
                    estimatedEndDate: Date(),
                    progress: 1.0,
                    isIgnition: true,
                    isWoodActive: isWoodActive,
                    powerLevel: powerLevel,
                    statusDetail: "Soll-Temperatur wird angefahren"
                )
                
                Task {
                    let content = ActivityContent(state: completedState, staleDate: nil)
                    await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(45)))
                    self.resetState()
                }
            }
            
        case .standby, .error:
            if currentActivity != nil {
                endLiveActivity(dismissalPolicy: .immediate)
            }
        }
    }
    
    // MARK: - Ignition Lifecycle
    
    private func startOrUpdateIgnition(
        phaseName: String,
        exhaustTemp: Double,
        roomTemp: Double,
        targetTemp: Double,
        powerLevel: Int,
        isWoodActive: Bool
    ) {
        let now = Date()
        
        // Neues Zündungsfenster starten, wenn noch keine Aktivität läuft oder vorher ein anderer Modus aktiv war
        if currentActivity == nil || currentContentState?.isIgnition != true {
            self.phaseStartDate = now
            self.estimatedEndDate = now.addingTimeInterval(Self.defaultIgnitionDuration)
        }
        
        let start = phaseStartDate ?? now
        let end = estimatedEndDate ?? now.addingTimeInterval(Self.defaultIgnitionDuration)
        let totalSpan = max(60.0, end.timeIntervalSince(start))
        let elapsed = max(0.0, now.timeIntervalSince(start))
        let progress = min(0.95, max(0.05, elapsed / totalSpan))
        
        let detail: String
        if exhaustTemp < 50.0 {
            detail = "Heizelement glüht & Pellets dosieren"
        } else if exhaustTemp < 90.0 {
            detail = "Flammenbildung erkannt, Gebläse regelt hoch"
        } else {
            detail = "Stabilisierung & Übergang zu P\(powerLevel)"
        }
        
        let state = StoveActivityAttributes.ContentState(
            phaseName: phaseName,
            targetPhaseName: "Heizbetrieb",
            exhaustTemp: exhaustTemp,
            roomTemp: roomTemp,
            targetTemp: targetTemp,
            startDate: start,
            estimatedEndDate: end,
            progress: progress,
            isIgnition: true,
            isWoodActive: isWoodActive,
            powerLevel: powerLevel,
            statusDetail: detail
        )
        
        if let activity = currentActivity {
            // Update existierender Activity
            self.currentContentState = state
            self.currentPhase = phaseName
            Task {
                let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(30))
                await activity.update(content)
            }
        } else {
            // Neue Activity anfordern
            let attributes = StoveActivityAttributes()
            do {
                let activity = try Activity<StoveActivityAttributes>.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
                self.currentActivity = activity
                self.activeActivityId = activity.id
                self.currentContentState = state
                self.currentPhase = phaseName
            } catch {
                print("StoveLiveActivityManager: Fehler beim Starten der Live Activity: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Burnout / Cleaning Lifecycle
    
    private func startOrUpdateBurnout(
        phaseName: String,
        exhaustTemp: Double,
        roomTemp: Double,
        targetTemp: Double
    ) {
        let now = Date()
        
        if currentActivity == nil || currentContentState?.isIgnition != false {
            self.phaseStartDate = now
            self.estimatedEndDate = now.addingTimeInterval(Self.defaultBurnoutDuration)
        }
        
        let start = phaseStartDate ?? now
        let end = estimatedEndDate ?? now.addingTimeInterval(Self.defaultBurnoutDuration)
        let totalSpan = max(60.0, end.timeIntervalSince(start))
        let elapsed = max(0.0, now.timeIntervalSince(start))
        let progress = min(0.95, max(0.05, elapsed / totalSpan))
        
        let detail = exhaustTemp > 80.0
            ? "Rauchgasgebläse kühlt Brennraum ab (\(Int(exhaustTemp))°C)"
            : "Nachlaufkühlung & Ascherost-Positionierung"
        
        let state = StoveActivityAttributes.ContentState(
            phaseName: phaseName,
            targetPhaseName: "Aus / Abgekühlt",
            exhaustTemp: exhaustTemp,
            roomTemp: roomTemp,
            targetTemp: targetTemp,
            startDate: start,
            estimatedEndDate: end,
            progress: progress,
            isIgnition: false,
            isWoodActive: false,
            powerLevel: 0,
            statusDetail: detail
        )
        
        if let activity = currentActivity {
            self.currentContentState = state
            self.currentPhase = phaseName
            Task {
                let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(30))
                await activity.update(content)
            }
        } else {
            let attributes = StoveActivityAttributes()
            do {
                let activity = try Activity<StoveActivityAttributes>.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
                self.currentActivity = activity
                self.activeActivityId = activity.id
                self.currentContentState = state
                self.currentPhase = phaseName
            } catch {
                print("StoveLiveActivityManager: Fehler beim Starten des Ausbrand-Live-Widgets: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Teardown
    
    public func endLiveActivity(dismissalPolicy: ActivityUIDismissalPolicy = .default) {
        guard let activity = currentActivity else { return }
        
        let finalState = currentContentState ?? StoveActivityAttributes.ContentState()
        Task {
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: dismissalPolicy)
            self.resetState()
        }
    }
    
    private func resetState() {
        self.currentActivity = nil
        self.activeActivityId = nil
        self.currentContentState = nil
        self.currentPhase = nil
        self.phaseStartDate = nil
        self.estimatedEndDate = nil
    }
}
