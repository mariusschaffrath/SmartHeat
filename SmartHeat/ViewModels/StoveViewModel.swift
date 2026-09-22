//
//  StoveViewModel.swift
//  SmartHeat
//
//  Central ViewModel for SmartHeat - Pure Cloud Architecture
//  Connects directly via HTTPS to Azure Cloud API (wifi4heat.azurewebsites.net).
//

import Foundation
import SwiftUI
import Combine

public enum StoveOperationalState: String, CaseIterable {
    case off = "Aus"
    case on = "Ein"
    case standby = "Standby"
    case igniting = "Zündung"
    case error = "Störung"
    
    public var title: String {
        switch self {
        case .off: return "Aus"
        case .on: return "Ein"
        case .standby: return "Standby"
        case .igniting: return "Zündung"
        case .error: return "Störung"
        }
    }
    
    public var color: Color {
        switch self {
        case .off: return Color.gray
        case .on: return Color.orange
        case .standby: return Color.green
        case .igniting: return Color.yellow
        case .error: return Color.red
        }
    }
}

@MainActor
class StoveViewModel: ObservableObject {
    @Published var bleManager = BLEManager()
    @Published var cloudService = CloudService()
    @Published var authService = AuthService()
    @Published var pelletManager = PelletTankManager()
    @Published var historyManager = TemperatureHistoryManager.shared
    @Published var haService = HomeAssistantService.shared
    
    // MARK: - Hardware Alarm & Sblocco State (Dielle 2ways / TiEmme)
    @Published var stoveErrorCode: Int = 0
    @Published var isStoveLockedByAlarm: Bool = false
    @Published var activeHardwareAlarm: DielleHardwareAlarm? = nil
    @Published var isUnlocking: Bool = false
    
    // MARK: - Diagnostics & Maintenance (Feature 3)
    @Published var diagnostics = StoveDiagnostics()
    
    // MARK: - Wood Combustion Tracking (Feature 4)
    @Published var woodTracker = WoodCombustionTracker.shared
    
    @Published var stoveStatus: String = "Aus"
    @Published var operationalState: StoveOperationalState = .off
    @Published var currentTemp: Double = 0.0
    @Published var waterTemp: Double = 0.0
    @Published var targetTemp: Double = 22.0
    @Published var exhaustTemp: Double = 0.0
    @Published var waterPressure: Double = 0.0
    @Published var powerLevel: Int = 3
    @Published var effectivePowerLevel: Int = 3
    @Published var isAutoPower: Bool = false
    @Published var effectivePowerDisplay: String = "Stufe 3"
    @Published var kanal1FanSpeed: Int = UserDefaults.standard.integer(forKey: "saved_kanal1_speed") != 0 ? UserDefaults.standard.integer(forKey: "saved_kanal1_speed") : 1
    @Published var kanal2FanSpeed: Int = UserDefaults.standard.integer(forKey: "saved_kanal2_speed") != 0 ? UserDefaults.standard.integer(forKey: "saved_kanal2_speed") : 1
    @Published var selectedFanChannel: Int = 1 // 1 = Kanal 1 (Flur), 2 = Kanal 2
    @Published var syncFanChannels: Bool = true
    
    var flurFanSpeed: Int {
        get { selectedFanChannel == 1 ? kanal1FanSpeed : kanal2FanSpeed }
        set { setKanalFanSpeed(channel: selectedFanChannel, speed: newValue) }
    }
    
    var isHeating: Bool {
        operationalState == .on
    }
    
    var isIgniting: Bool {
        operationalState == .igniting
    }
    
    var isStandby: Bool {
        operationalState == .standby
    }
    
    var isOff: Bool {
        operationalState == .off
    }
    
    var isFaulted: Bool {
        operationalState == .error || isStoveLockedByAlarm
    }
    
    var isWoodMode: Bool {
        (operationalState == .on && stoveStatus == "Scheitholz") || woodTracker.isWoodActive
    }
    
    @Published var isTargetLocked: Bool = true {
        didSet {
            if !isTargetLocked {
                resetAutoLockTimer()
            } else {
                autoLockWorkItem?.cancel()
            }
        }
    }
    
    private var autoLockWorkItem: DispatchWorkItem?
    
    /// Sperrt das Zieltemperatur-Panel nach 1 Minute Inaktivität automatisch wieder
    func resetAutoLockTimer() {
        autoLockWorkItem?.cancel()
        guard !isTargetLocked else { return }
        
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                self.isTargetLocked = true
            }
            print("AUTO-LOCK: Zieltemperatur-Panel nach 1 Minute Inaktivität automatisch gesperrt.")
        }
        autoLockWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 60.0, execute: item)
    }
    
    // Optimistic Target Locking (Verhindert Zurückspringen alter Cloud-Werte)
    @Published var pendingTargetTemp: Double?
    private var pendingTargetTime: Date = Date.distantPast
    
    @Published var pendingKanal1Speed: Int?
    private var pendingKanal1Time: Date = Date.distantPast
    
    var hasPendingTargetSync: Bool {
        pendingTargetTemp != nil
    }
    
    @Published var activeError: StoveError?
    @Published var isSyncing: Bool = false
    
    private let interactionLockDuration: TimeInterval = 25.0
    
    @Published var isWaterStove: Bool = UserDefaults.standard.bool(forKey: "is_water_stove") {
        didSet { UserDefaults.standard.set(isWaterStove, forKey: "is_water_stove") }
    }
    
    // Feature Flag: Pellet Tank tracking
    @Published var isPelletTankEnabled: Bool = UserDefaults.standard.bool(forKey: "enable_pellet_tank_feature") {
        didSet { UserDefaults.standard.set(isPelletTankEnabled, forKey: "enable_pellet_tank_feature") }
    }
    
    // Numeric Serial Number (e.g. "25016460")
    @Published var deviceId: String = UserDefaults.standard.string(forKey: "saved_device_id") ?? "25016460" {
        didSet { UserDefaults.standard.set(deviceId, forKey: "saved_device_id") }
    }
    
    // 36-character DeviceKey GUID (required for Cloud API REST calls)
    @Published var cloudGuid: String = UserDefaults.standard.string(forKey: "saved_cloud_guid") ?? "" {
        didSet { UserDefaults.standard.set(cloudGuid, forKey: "saved_cloud_guid") }
    }
    
    // 6-digit Stove PIN
    @Published var stovePin: String = UserDefaults.standard.string(forKey: "saved_stove_pin") ?? "270962" {
        didSet { UserDefaults.standard.set(stovePin, forKey: "saved_stove_pin") }
    }
    
    @Published var lastRawMessage: String = ""
    
    private var lastUserInteraction: Date = Date.distantPast
    
    func triggerInteractionLock() {
        lastUserInteraction = Date()
        resetAutoLockTimer()
    }
    
    private func isInteractionLocked() -> Bool {
        return Date().timeIntervalSince(lastUserInteraction) < interactionLockDuration
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: AnyCancellable?
    private var currentSyncTask: Task<Void, Never>?
    
    init() {
        setupSubscriptions()
        loadSavedData()
        configureEndpoints()
        startPolling()
        attemptAutoLogin()
        historyManager.seedInitialDataIfNeeded(
            currentRoom: currentTemp > 0 ? currentTemp : 21.6,
            currentExhaust: exhaustTemp > 0 ? exhaustTemp : 135.0,
            targetRoom: targetTemp
        )
        
        if haService.isEnabled && !haService.accessToken.isEmpty {
            Task { [weak self] in
                await self?.syncHomeAssistantData()
            }
        }
    }
    
    func configureEndpoints() {
        let cloudBase = "https://wifi4heat.azurewebsites.net"
        authService.setBaseURL(cloudBase)
        cloudService.setBaseURL("\(cloudBase)/api/devices")
    }
    
    private func attemptAutoLogin() {
        guard let email = KeychainService.shared.load(key: "cloud_email"),
              let password = KeychainService.shared.load(key: "cloud_password") else { return }
        Task {
            do {
                try await authService.login(email: email, password: password)
                self.updateCloudGuidFromDevices()
            } catch {
                print("Cloud Auto-login failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupSubscriptions() {
        authService.objectWillChange
            .sink { [weak self] _ in
                self?.updateCloudGuidFromDevices()
                self?.forwardErrors()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        cloudService.objectWillChange
            .sink { [weak self] _ in
                self?.forwardErrors()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        pelletManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        historyManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        Publishers.CombineLatest($currentTemp, $exhaustTemp)
            .sink { [weak self] room, exh in
                self?.historyManager.recordTelemetry(roomTemp: room, exhaustTemp: exh)
            }
            .store(in: &cancellables)
    }
    
    private func forwardErrors() {
        if let err = authService.activeError {
            self.activeError = err
        } else if let err = cloudService.activeError {
            self.activeError = err
        }
    }
    
    private func updateCloudGuidFromDevices() {
        if let first = authService.devices.first {
            let numericId = first.serialNumber ?? (first.id.count <= 10 && !first.id.isEmpty ? first.id : "25016460")
            if !numericId.isEmpty && self.deviceId != numericId {
                self.deviceId = numericId
                UserDefaults.standard.set(numericId, forKey: "saved_device_id")
                print("CONFIG: Ofen-ID \(numericId) automatisch aus Cloud bezogen und gespeichert.")
            }
            
            if !first.id.isEmpty && self.cloudGuid != first.id {
                self.cloudGuid = first.id
                UserDefaults.standard.set(first.id, forKey: "saved_cloud_guid")
                print("CONFIG: GUID \(first.id) aus Cloud-Geräten übernommen.")
            }
        }
    }
    
    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshData() }
    }
    
    /// Pausiert den Polling-Timer und bricht laufende Sync-Tasks ab (z.B. bei App im Hintergrund)
    func pausePolling() {
        pollTimer?.cancel()
        pollTimer = nil
        currentSyncTask?.cancel()
        currentSyncTask = nil
        isSyncing = false
        print("LIFECYCLE: Polling pausiert (App im Hintergrund / Inaktiv).")
    }
    
    /// Reaktiviert das Polling beim Zurückkehren in den Vordergrund
    func resumePolling() {
        pausePolling()
        print("LIFECYCLE: Polling reaktiviert (App aktiv).")
        startPolling()
        refreshData()
    }
    
    func refreshData() {
        guard authService.isAuthenticated, let token = authService.token else { return }
        guard !isSyncing else { return } // Verhindert das Anhäufen paralleler Anfragen
        let keyToUse = deviceId.isEmpty ? "25016460" : deviceId
        self.isSyncing = true
        
        currentSyncTask?.cancel()
        currentSyncTask = Task { [weak self] in
            defer {
                self?.isSyncing = false
            }
            guard let self = self else { return }
            do {
                if let data = try await self.cloudService.fetchStoveUpdate(deviceKey: keyToUse, token: token) {
                    guard !Task.isCancelled else { return }
                    if let mapped = data.getMappedValues() {
                        self.currentTemp = mapped.room
                        self.exhaustTemp = mapped.exhaust
                        
                        // Optimistic Confirmation Check for Target Temperature (verhindert Zurückspringen)
                        if let pending = self.pendingTargetTemp {
                            if abs(mapped.target - pending) < 0.2 {
                                self.pendingTargetTemp = nil
                                self.targetTemp = mapped.target
                                print("SYNC: Zieltemperatur \(mapped.target)°C vom Ofen bestätigt!")
                            } else if Date().timeIntervalSince(self.pendingTargetTime) < 45.0 {
                                self.targetTemp = pending
                            } else {
                                self.pendingTargetTemp = nil
                                self.targetTemp = mapped.target
                            }
                        } else if !self.isInteractionLocked() && mapped.target > 0 {
                            self.targetTemp = mapped.target
                        }
                        
                        self.waterTemp = mapped.water
                        self.waterPressure = mapped.pressure
                        self.powerLevel = mapped.powerLevel
                        self.effectivePowerLevel = mapped.effectivePower
                        self.isAutoPower = (mapped.powerLevel == 6)
                        if mapped.status == 0 {
                            self.effectivePowerDisplay = "Aus"
                        } else if mapped.status == 6 {
                            self.effectivePowerDisplay = "Stufe 1 (Modulation)"
                        } else if self.isAutoPower {
                            self.effectivePowerDisplay = "Auto (Stufe \(mapped.effectivePower))"
                        } else {
                            self.effectivePowerDisplay = "Stufe \(mapped.powerLevel)"
                        }
                        
                        // Optimistic Confirmation Check for Kanal 1 Fan Speed
                        if let pendingFan = self.pendingKanal1Speed {
                            if mapped.kanal1 == pendingFan {
                                self.pendingKanal1Speed = nil
                                self.kanal1FanSpeed = mapped.kanal1
                                print("SYNC: Kanalgebläse Stufe \(mapped.kanal1) vom Ofen bestätigt!")
                            } else if Date().timeIntervalSince(self.pendingKanal1Time) < 45.0 {
                                self.kanal1FanSpeed = pendingFan
                            } else {
                                self.pendingKanal1Speed = nil
                                if mapped.kanal1 >= 0 {
                                    self.kanal1FanSpeed = mapped.kanal1
                                }
                            }
                        } else if !self.isInteractionLocked() {
                            if mapped.kanal1 >= 0 {
                                self.kanal1FanSpeed = mapped.kanal1
                            }
                        }
                        
                        if !self.isInteractionLocked() && mapped.kanal2 >= 0 {
                            self.kanal2FanSpeed = mapped.kanal2
                        }
                        self.updateStatusLabel(mapped.status, errorCode: mapped.errorCode)
                        
                        // Alarm Handling: Status 8 (Sicurezza), Status 9 (Blocco), Status 10 (Errore), oder errorCode > 0
                        if mapped.errorCode > 0 {
                            self.stoveErrorCode = mapped.errorCode
                            let alarm = DielleHardwareAlarm.from(code: mapped.errorCode)
                            self.activeHardwareAlarm = alarm
                            self.isStoveLockedByAlarm = true
                            if let alarm = alarm {
                                StoveErrorLogManager.shared.logError(
                                    code: alarm.codeString,
                                    customDetail: "\(alarm.description)\nEmpfohlene Behebung: \(alarm.remedy)"
                                )
                            }
                        } else if mapped.status == 8 || mapped.status == 9 {
                            self.isStoveLockedByAlarm = true
                            let alarm = DielleHardwareAlarm(
                                code: 99,
                                codeString: "BLOCK",
                                title: "Ofen verriegelt (Sicherheitsabschaltung)",
                                description: "Die Platine meldet eine Sicherheitsabschaltung / Blockierung.",
                                remedy: "Brennkammer kontrollieren und Störung quittieren."
                            )
                            self.activeHardwareAlarm = alarm
                            StoveErrorLogManager.shared.logError(code: "BLOCK", customDetail: alarm.description)
                        } else {
                            self.stoveErrorCode = 0
                            self.isStoveLockedByAlarm = false
                            self.activeHardwareAlarm = nil
                        }
                        
                        if self.isPelletTankEnabled {
                            self.pelletManager.updateTracking(statusCode: mapped.status, powerLevel: mapped.effectivePower, isWood: mapped.isWood)
                        }
                        self.woodTracker.update(statusCode: mapped.status, exhaustTemp: mapped.exhaust)
                        self.lastRawMessage = "Cloud Live-Daten empfangen."
                    } else if let vals = data.values ?? data.data {
                        if let r = vals["I30006"] ?? vals["30006"], let rv = Double(r) { self.currentTemp = rv / 10.0 }
                        if !self.isInteractionLocked() {
                            if let t = vals["A20493"] ?? vals["20493"], let tv = Double(t) {
                                self.targetTemp = tv / 10.0
                            }
                        }
                    }
                } else {
                    self.lastRawMessage = "Cloud: Warte auf Azure-Antwort (ID: \(keyToUse))..."
                }
            } catch {
                print("Cloud Refresh Error: \(error)")
                if (error as NSError).code == 401 || "\(error)".contains("401") {
                    self.attemptAutoLogin()
                }
            }
        }
    }
    
    private func updateStatusLabel(_ code: Int, errorCode: Int = 0) {
        if errorCode > 0 || code == 8 || code == 9 {
            let codeStr = errorCode > 0 ? String(format: "Er%02d", errorCode) : "Blockiert"
            stoveStatus = "Störung (\(codeStr))"
            operationalState = .error
            return
        }
        
        switch code {
        case 0:
            stoveStatus = "Aus"
            operationalState = .off
        case 1, 2, 3, 4:
            stoveStatus = (code == 2) ? "Zündung" : "Zündung / Start"
            operationalState = .igniting
        case 5, 13:
            stoveStatus = (code == 13) ? "Scheitholz" : "Ein"
            operationalState = .on
        case 6, 7:
            stoveStatus = (code == 6) ? "Modulation" : "Ausbrand"
            operationalState = (code == 6) ? .on : .off
        case 10:
            stoveStatus = "Ascheentleerung / Reinigung"
            operationalState = .off
        case 11:
            stoveStatus = "Standby"
            operationalState = .standby
        default:
            if code > 0 {
                stoveStatus = "Ein"
                operationalState = .on
            } else {
                stoveStatus = "Aus"
                operationalState = .off
            }
        }
    }
    
    // MARK: - Alarm Quittierung & Entsperren (Sblocco)
    /// Quittiert anstehende Hardware-Alarme auf der TiEmme Platine über das Dielle Sblocco-Kommando (050a0000)
    /// SICHERHEITSHINWEIS: Dieser Befehl quittiert ausschließlich den Fehlerspeicher und entsperrt den Ofen.
    /// Er führt KEINE Zündung durch.
    func unlockStoveAlarm() async {
        guard !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        
        print("DIELLE: Sende Entsperrbefehl .unlock (050a0000)...")
        // Befehl mit Burst-Folgeabfragen senden
        sendUniversalWithBurst(command: .unlock)
        
        // Störung in der Historie als quittiert vermerken
        if let alarm = activeHardwareAlarm {
            StoveErrorLogManager.shared.logError(
                code: alarm.codeString,
                customDetail: "Alarm durch Benutzer quittiert. Sblocco-Entsperrbefehl (050a0000) an Ofen übermittelt."
            )
            for entry in StoveErrorLogManager.shared.errorLog where entry.code == alarm.codeString && !entry.isResolved {
                StoveErrorLogManager.shared.markResolved(id: entry.id)
            }
        }
        
        // Optimistisch Fehlerzustand zurücksetzen
        self.isStoveLockedByAlarm = false
        self.activeHardwareAlarm = nil
        self.stoveErrorCode = 0
        if self.operationalState == .error {
            self.operationalState = .off
            self.stoveStatus = "Aus"
        }
        
        // Haptisches Feedback (Erfolg)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Nach 2 Sekunden Live-Status abfragen
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await MainActor.run {
            self.refreshData()
        }
    }
    
    func turnOn() { 
        triggerInteractionLock()
        operationalState = .igniting
        stoveStatus = "Zündung"
        sendUniversal(command: .turnOn) 
    }
    
    func turnOff() { 
        triggerInteractionLock()
        operationalState = .off
        stoveStatus = "Aus"
        sendUniversal(command: .turnOff) 
    }
    
    func setTemperature(_ value: Double) {
        guard !isTargetLocked else { return }
        setTargetTempDirect(value)
    }
    
    func incrementTargetTemp() {
        guard !isTargetLocked else { return }
        let roundedCurrent = (targetTemp * 2).rounded() / 2
        let newTemp = min(35.0, roundedCurrent + 0.5)
        setTargetTempDirect(newTemp)
    }
    
    func decrementTargetTemp() {
        guard !isTargetLocked else { return }
        let roundedCurrent = (targetTemp * 2).rounded() / 2
        let newTemp = max(10.0, roundedCurrent - 0.5)
        setTargetTempDirect(newTemp)
    }
    
    func setTargetTempDirect(_ value: Double) {
        let rounded = (value * 2).rounded() / 2
        triggerInteractionLock()
        resetAutoLockTimer()
        self.pendingTargetTemp = rounded
        self.pendingTargetTime = Date()
        self.targetTemp = rounded
        sendUniversalWithBurst(command: StoveCommand.writeParameter(value: Int(rounded * 10)))
    }
    
    func setKanalFanSpeed(channel: Int, speed: Int) {
        triggerInteractionLock()
        let clamped = max(0, min(7, speed))
        
        if syncFanChannels {
            self.kanal1FanSpeed = clamped
            self.kanal2FanSpeed = clamped
            self.pendingKanal1Speed = clamped
            self.pendingKanal1Time = Date()
            UserDefaults.standard.set(clamped, forKey: "saved_kanal1_speed")
            UserDefaults.standard.set(clamped, forKey: "saved_kanal2_speed")
            sendUniversalWithBurst(command: StoveCommand.writeParameter(id: "023f", value: clamped))
            sendUniversal(command: StoveCommand.writeParameter(id: "027e", value: clamped))
        } else {
            if channel == 1 {
                // Luftheizung Flur (Riscaldamento) ist Register 023f
                self.kanal1FanSpeed = clamped
                self.pendingKanal1Speed = clamped
                self.pendingKanal1Time = Date()
                UserDefaults.standard.set(clamped, forKey: "saved_kanal1_speed")
                sendUniversalWithBurst(command: StoveCommand.writeParameter(id: "023f", value: clamped))
            } else {
                // Zusatzkanal / Luftzufuhr ist Register 027e
                self.kanal2FanSpeed = clamped
                UserDefaults.standard.set(clamped, forKey: "saved_kanal2_speed")
                sendUniversal(command: StoveCommand.writeParameter(id: "027e", value: clamped))
            }
        }
    }
    
    func setFlurFanSpeed(_ speed: Int) {
        setKanalFanSpeed(channel: 1, speed: speed)
    }
    
    private func sendUniversal(command: StoveCommand) {
        guard authService.isAuthenticated, let token = authService.token else {
            print("Cloud nicht angemeldet. Befehl lokal gemockt: \(command.rawString)")
            return
        }
        
        let keyToUse = deviceId.isEmpty ? "25016460" : deviceId

        Task {
            do {
                try await cloudService.sendCommand(deviceKey: keyToUse, token: token, command: command)
                try await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { self.refreshData() }
            } catch {
                print("Cloud Command Error: \(error.localizedDescription)")
                let err = StoveError.cloudNetworkError(message: "Befehl konnte nicht gesendet werden: \(error.localizedDescription)")
                await MainActor.run { self.activeError = err }
            }
        }
    }
    
    /// Sendet Befehl und führt eine schnelle Folgeabfrage durch (1.5s, 3.5s, 6.0s), um die Synchronisationszeit drastisch zu verkürzen
    private func sendUniversalWithBurst(command: StoveCommand) {
        guard authService.isAuthenticated, let token = authService.token else {
            print("Cloud nicht angemeldet. Befehl lokal gemockt: \(command.rawString)")
            return
        }
        
        let keyToUse = deviceId.isEmpty ? "25016460" : deviceId
        self.isSyncing = true

        Task {
            do {
                try await cloudService.sendCommand(deviceKey: keyToUse, token: token, command: command)
                
                let delays: [UInt64] = [1_500_000_000, 2_000_000_000, 2_500_000_000]
                for delay in delays {
                    try await Task.sleep(nanoseconds: delay)
                    await MainActor.run { self.refreshData() }
                    let confirmed = await MainActor.run { self.pendingTargetTemp == nil && self.pendingKanal1Speed == nil }
                    if confirmed {
                        break
                    }
                }
                await MainActor.run { self.isSyncing = false }
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                    print("Cloud Command Error: \(error.localizedDescription)")
                    let err = StoveError.cloudNetworkError(message: "Befehl konnte nicht gesendet werden: \(error.localizedDescription)")
                    self.activeError = err
                }
            }
        }
    }
    
    private func loadSavedData() {
        if let savedToken = UserDefaults.standard.string(forKey: "cloud_token") {
            authService.token = savedToken
            authService.isAuthenticated = true
        }
    }
    
    func logout() {
        authService.logout()
        cloudService.activeError = nil
        self.activeError = nil
        KeychainService.shared.remove(key: "cloud_email")
        KeychainService.shared.remove(key: "cloud_password")
        UserDefaults.standard.removeObject(forKey: "cloud_token")
        UserDefaults.standard.set(false, forKey: "has_saved_account")
    }
    
    // MARK: - Home Assistant 24/7 Synchronization
    func syncHomeAssistantData() async {
        guard haService.isEnabled && !haService.accessToken.isEmpty else { return }
        do {
            let (roomPoints, exhaustPoints) = try await haService.fetchTemperatureHistory(days: 30)
            if !roomPoints.isEmpty || !exhaustPoints.isEmpty {
                self.historyManager.updateWithHomeAssistantData(roomPoints: roomPoints, exhaustPoints: exhaustPoints)
                print("HA SYNC: \(roomPoints.count) Raum- und \(exhaustPoints.count) Abgaspunkte geladen.")
            }
            
            if let pellet = try await haService.fetchPelletState() {
                self.pelletManager.syncFromHomeAssistant(levelKg: pellet.levelKg)
                print("HA SYNC: Pelletstand \(pellet.levelKg) kg (\(pellet.percent)%) synchronisiert.")
            }
        } catch {
            print("HA SYNC Error: \(error.localizedDescription)")
        }
    }
}
