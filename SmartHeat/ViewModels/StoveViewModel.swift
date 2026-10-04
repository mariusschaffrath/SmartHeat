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
import UIKit

public enum StoveOperationalState: String, CaseIterable {
    case off = "Aus"
    case on = "Heizbetrieb"
    case standby = "Standby"
    case igniting = "Zündung"
    case error = "Störung"
    
    public var title: String {
        switch self {
        case .off: return "Aus"
        case .on: return "Heizbetrieb"
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
    @Published var socketService = StoveSocketService()
    @Published var scheduleManager = HeatingScheduleManager.shared
    @Published var liveActivityManager = StoveLiveActivityManager.shared
    
    // MARK: - Concurrency & Task Management (Hürde 5.3)
    @MainActor private var burstSyncTask: Task<Void, Never>?
    
    // MARK: - Dual-Path Connection (Hürde 2.1)
    public enum ConnectionPath: String, CaseIterable, Sendable {
        case localSocket = "localSocket"
        case cloud = "cloud"
        
        public var title: String {
            switch self {
            case .localSocket: return "Lokales WLAN (Port 80)"
            case .cloud: return "Dielle Cloud (Azure)"
            }
        }
        
        public var shortTitle: String {
            switch self {
            case .localSocket: return "Lokal"
            case .cloud: return "Cloud"
            }
        }
        
        public var icon: String {
            switch self {
            case .localSocket: return "wifi"
            case .cloud: return "cloud.fill"
            }
        }
    }
    
    // MARK: - Exklusive Cloud-Synchronisation
    public enum ConnectionMode: String, CaseIterable, Sendable {
        case forceCloud = "forceCloud"
        
        public var title: String {
            return "Dielle Cloud (Exklusiv)"
        }
        
        public var description: String {
            return "SmartHeat kommuniziert ausschließlich und stabil über die offizielle Dielle Azure Cloud."
        }
    }
    
    @Published var connectionMode: ConnectionMode = .forceCloud
    @Published var connectionPath: ConnectionPath = .cloud
    @Published var stoveLocalIP: String = UserDefaults.standard.string(forKey: "stove_local_ip") ?? "192.168.178.188" {
        didSet {
            UserDefaults.standard.set(stoveLocalIP, forKey: "stove_local_ip")
            socketService.setHost(stoveLocalIP)
        }
    }
    
    // MARK: - Hardware Alarm & Sblocco State (Dielle 2ways / TiEmme)
    @Published var stoveErrorCode: Int = 0
    @Published var isStoveLockedByAlarm: Bool = false
    @Published var activeHardwareAlarm: DielleHardwareAlarm? = nil
    @Published var isUnlocking: Bool = false
    
    // MARK: - Diagnostics & Maintenance (Feature 3 & Hürde 3.4)
    public static let diagnosticsStorageKey = "stove_diagnostics_data"
    @Published var diagnostics: StoveDiagnostics = StoveDiagnostics()
    private var lastDiagnosticsTrackingDate: Date?
    private var isIgnitionCounted: Bool = false
    
    func loadDiagnostics() {
        if let data = UserDefaults.standard.data(forKey: Self.diagnosticsStorageKey),
           let saved = try? JSONDecoder().decode(StoveDiagnostics.self, from: data) {
            self.diagnostics = saved
        } else {
            self.diagnostics = StoveDiagnostics()
        }
    }
    
    func saveDiagnostics() {
        if let encoded = try? JSONEncoder().encode(diagnostics) {
            UserDefaults.standard.set(encoded, forKey: Self.diagnosticsStorageKey)
        }
    }
    
    func updateDiagnosticsTracking(statusCode: Int, deltaSeconds: TimeInterval? = nil) {
        let now = Date()
        
        // Zähler für erfolgreiche Zündungen: Reset bei Aus/Standby (0, 9, 11), Erhöhung bei Zündung (1, 2)
        if statusCode == 0 || statusCode == 9 || statusCode == 11 {
            isIgnitionCounted = false
        } else if !isIgnitionCounted && (statusCode == 1 || statusCode == 2) {
            diagnostics.ignitionCount += 1
            isIgnitionCounted = true
            saveDiagnostics()
        }
        
        let delta: TimeInterval
        if let explicit = deltaSeconds {
            delta = explicit
            lastDiagnosticsTrackingDate = now
        } else if let last = lastDiagnosticsTrackingDate {
            delta = now.timeIntervalSince(last)
            lastDiagnosticsTrackingDate = now
        } else {
            lastDiagnosticsTrackingDate = now
            return
        }
        
        guard delta > 0 && delta <= 7200 else { return }
        
        // Akkumulation von Brennstunden (z.B. wenn Status 1..6 oder 13 aktiv ist)
        let isBurning = (1...6).contains(statusCode) || statusCode == 13
        if isBurning {
            diagnostics.heatingSeconds += delta
            diagnostics.totalOperatingSeconds += delta
            
            let newHeatingHours = Int(diagnostics.heatingSeconds / 3600.0)
            let newTotalHours = Int(diagnostics.totalOperatingSeconds / 3600.0)
            
            if newHeatingHours != diagnostics.heatingHours || newTotalHours != diagnostics.totalOperatingHours {
                diagnostics.heatingHours = newHeatingHours
                diagnostics.totalOperatingHours = newTotalHours
                saveDiagnostics()
            }
        }
    }
    
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
        (operationalState == .on && (stoveStatus == "Scheitholz" || stoveStatus == "Scheitholzbetrieb")) || woodTracker.isWoodActive
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
    
    // MARK: - Akku- & Energie-Effizienz (Adaptive Polling & Stromsparmodus)
    @Published var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var isEcoModeEnabled: Bool = UserDefaults.standard.object(forKey: "stove_eco_polling_enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEcoModeEnabled, forKey: "stove_eco_polling_enabled")
            restartPollingTimerIfNeeded()
        }
    }
    
    private var lastUserInteraction: Date = Date.distantPast
    var lastInteractionBurstDate: Date = Date()
    private var activePollingInterval: TimeInterval = 10.0
    
    func triggerInteractionLock() {
        lastUserInteraction = Date()
        lastInteractionBurstDate = Date()
        resetAutoLockTimer()
        restartPollingTimerIfNeeded()
    }
    
    var isUserInteracting: Bool {
        Date().timeIntervalSince(lastInteractionBurstDate) < 90.0
    }
    
    var isStoveActive: Bool {
        return stoveErrorCode != 0 || operationalState != .off || exhaustTemp > 50.0
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
        Task { [weak self] in
            await self?.evaluateConnectionPath()
        }
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
    
    nonisolated deinit {}
    
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
            
        // Lifecycle & Akku-Optimierung: Polling bei App-Hintergrund sofort stoppen
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.pausePolling()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.lastInteractionBurstDate = Date()
                self?.restartPollingTimerIfNeeded()
                self?.resumePolling()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSNotification.Name.NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                self?.restartPollingTimerIfNeeded()
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
    
    // MARK: - Exklusive Cloud-Synchronisation & Polling
    func evaluateConnectionPath() async {
        if self.connectionPath != .cloud {
            self.connectionPath = .cloud
            restartPollingTimer()
        }
    }
    
    var currentPollingInterval: TimeInterval {
        guard isEcoModeEnabled else {
            return 10.0
        }
        if connectionPath == .localSocket {
            return 3.0 // Legacy Fallback
        }
        // 1. Wenn Benutzer die App aktiv bedient -> Schnelle 10s (bzw. 15s im Stromsparmodus)
        if isUserInteracting {
            return isLowPowerMode ? 15.0 : 10.0
        }
        // 2. Wenn der Ofen brennt / heizt -> 10s (bzw. 15s im Stromsparmodus)
        if isStoveActive {
            return isLowPowerMode ? 15.0 : 10.0
        }
        // 3. Intelligenter Eco-Modus: Wenn Ofen AUS & Kalt ist -> 30s (bzw. 45s im Stromsparmodus)
        // Reduziert iPhone-Funkmodem-Aufweckzyklen drastisch und spart bis zu 75% Akku im Standby!
        return isLowPowerMode ? 45.0 : 30.0
    }
    
    func restartPollingTimerIfNeeded() {
        let targetInterval = currentPollingInterval
        if abs(activePollingInterval - targetInterval) > 1.0 {
            restartPollingTimer()
        }
    }
    
    private func startPolling() {
        guard pollTimer == nil else { return }
        let interval = currentPollingInterval
        activePollingInterval = interval
        pollTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshData()
                self?.evaluateHeatingSchedule()
                self?.restartPollingTimerIfNeeded()
            }
    }
    
    // MARK: - Heating Schedule Evaluation (Hürde 5.4)
    /// Periodische Überprüfung und automatische Nachführung des aktiven Wochen-Heizplans
    func evaluateHeatingSchedule() {
        guard scheduleManager.isScheduleActive else { return }
        guard !isInteractionLocked() else { return }
        guard pendingTargetTemp == nil else { return }
        
        guard let scheduledTemp = scheduleManager.getCurrentTargetTemperature() else { return }
        let roundedScheduled = (scheduledTemp * 2).rounded() / 2
        
        // Wenn sich der geplante Sollwert von der aktuellen Zieltemperatur unterscheidet
        if abs(self.targetTemp - roundedScheduled) >= 0.25 {
            print("SCHEDULE: Wende geplanten Sollwert an: \(roundedScheduled)°C (aktuell: \(self.targetTemp)°C)")
            self.setTargetTempDirect(roundedScheduled)
        }
    }
    
    func restartPollingTimer() {
        pollTimer?.cancel()
        pollTimer = nil
        startPolling()
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
        Task { [weak self] in
            await self?.evaluateConnectionPath()
            self?.refreshData()
        }
    }
    
    func refreshData() {
        guard !isSyncing else { return } // Verhindert das Anhäufen paralleler Anfragen
        self.isSyncing = true
        
        currentSyncTask?.cancel()
        currentSyncTask = Task { [weak self] in
            defer {
                self?.isSyncing = false
            }
            guard let self = self else { return }
            
            // Exklusiver Pfad: Azure Cloud API
            guard self.authService.isAuthenticated, let token = self.authService.token else { return }
            let keyToUse = self.deviceId.isEmpty ? "25016460" : self.deviceId
            
            do {
                if let data = try await self.cloudService.fetchStoveUpdate(deviceKey: keyToUse, token: token) {
                    guard !Task.isCancelled else { return }
                    if let mapped = data.getMappedValues() {
                        self.applyMappedValues(mapped, source: "Cloud (Azure)")
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
    
    // MARK: - Service Maintenance Reset
    /// Quittiert die durchgeführte 2.000h Wartung und startet das Intervall neu
    func resetServiceMaintenance() {
        diagnostics.resetService(operatingHours: diagnostics.totalOperatingHours)
        saveDiagnostics()
        objectWillChange.send()
        print("SERVICE: 2.000h Wartung erfolgreich quittiert bei \(diagnostics.totalOperatingHours) Betriebsstunden.")
    }
    
    func updateTelemetry(values: [String], source: String = "Live") {
        let data = CloudStoveData(deviceKey: nil, isOnline: true, values: nil, Values: values, data: nil)
        if let mapped = data.getMappedValues() {
            self.applyMappedValues(mapped, source: source)
        }
    }
    
    func applyMappedValues(_ mapped: (room: Double, exhaust: Double, target: Double, water: Double, pressure: Double, status: Int, powerLevel: Int, effectivePower: Int, flurFan: Int, kanal1: Int, kanal2: Int, isWood: Bool, errorCode: Int), source: String) {
        self.currentTemp = mapped.room
        self.exhaustTemp = mapped.exhaust
        
        // Optimistic Confirmation Check for Target Temperature (verhindert Zurückspringen)
        if let pending = self.pendingTargetTemp {
            if abs(mapped.target - pending) < 0.2 {
                self.pendingTargetTemp = nil
                self.targetTemp = mapped.target
                print("SYNC: Zieltemperatur \(mapped.target)°C vom Ofen bestätigt (\(source))!")
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
                print("SYNC: Kanalgebläse Stufe \(mapped.kanal1) vom Ofen bestätigt (\(source))!")
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
        self.updateDiagnosticsTracking(statusCode: mapped.status)
        self.evaluateHeatingSchedule()
        self.lastRawMessage = "\(source): Live-Daten empfangen."
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
            stoveStatus = (code == 1 ? "Zündung Phase 1" : (code == 2 ? "Zündung Phase 2" : (code == 3 ? "Zündung Phase 3" : "Stabilisierung")))
            operationalState = .igniting
        case 5:
            stoveStatus = "Heizbetrieb"
            operationalState = .on
        case 6:
            stoveStatus = "Modulation"
            operationalState = .on
        case 7:
            stoveStatus = "Ausbrand"
            operationalState = .off
        case 10:
            stoveStatus = "Ascheentleerung / Reinigung"
            operationalState = .off
        case 11:
            stoveStatus = "Standby"
            operationalState = .standby
        case 13:
            stoveStatus = "Scheitholzbetrieb"
            operationalState = .on
        default:
            if code > 0 {
                stoveStatus = "Heizbetrieb"
                operationalState = .on
            } else {
                stoveStatus = "Aus"
                operationalState = .off
            }
        }
        
        // ActivityKit Live Activity & Dynamic Island synchronisieren
        liveActivityManager.syncWithStove(
            operationalState: operationalState,
            stoveStatus: stoveStatus,
            exhaustTemp: exhaustTemp,
            roomTemp: currentTemp,
            targetTemp: targetTemp,
            powerLevel: effectivePowerLevel,
            isWoodActive: isWoodMode
        )
    }
    
    // MARK: - Alarm Quittierung & Entsperren (Sblocco)
    /// Quittiert anstehende Hardware-Alarme auf der TiEmme Platine über das Dielle Sblocco-Kommando (050a0000)
    /// SICHERHEITSHINWEIS: Dieser Befehl quittiert ausschließlich den Fehlerspeicher und entsperrt den Ofen.
    /// Er führt KEINE Zündung durch.
    func unlockStoveAlarm() async {
        guard !isUnlocking else { return }
        triggerInteractionLock()
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
        liveActivityManager.syncWithStove(
            operationalState: .igniting,
            stoveStatus: "Zündung",
            exhaustTemp: exhaustTemp,
            roomTemp: currentTemp,
            targetTemp: targetTemp,
            powerLevel: effectivePowerLevel,
            isWoodActive: isWoodMode
        )
        sendUniversal(command: .turnOn) 
    }
    
    func turnOff() { 
        triggerInteractionLock()
        operationalState = .off
        stoveStatus = "Ausbrand"
        liveActivityManager.syncWithStove(
            operationalState: .off,
            stoveStatus: "Ausbrand",
            exhaustTemp: exhaustTemp,
            roomTemp: currentTemp,
            targetTemp: targetTemp,
            powerLevel: effectivePowerLevel,
            isWoodActive: false
        )
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
        let clamped = max(0, min(6, speed))
        
        // Riscaldamento / Luftheizung Flur: Es darf ausschließlich Register 023f beschrieben werden!
        // Schutz vor Verbrennungsluft-Fehlkonfiguration: Register 027e (Brennraum Luftzufuhr 2) darf keinesfalls mitgeschrieben werden.
        self.kanal1FanSpeed = clamped
        self.pendingKanal1Speed = clamped
        self.pendingKanal1Time = Date()
        UserDefaults.standard.set(clamped, forKey: "saved_kanal1_speed")
        
        if syncFanChannels {
            self.kanal2FanSpeed = clamped
            UserDefaults.standard.set(clamped, forKey: "saved_kanal2_speed")
        }
        
        sendUniversalWithBurst(command: StoveCommand.writeParameter(id: "023f", value: clamped))
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
    
    /// Sendet Befehl über die Cloud und führt schnelle Folgeabfragen durch
    private func sendUniversalWithBurst(command: StoveCommand) {
        self.isSyncing = true
        burstSyncTask?.cancel()
        
        guard authService.isAuthenticated, let token = authService.token else {
            print("Cloud nicht angemeldet. Befehl lokal gemockt: \(command.rawString)")
            self.isSyncing = false
            return
        }
        
        let keyToUse = deviceId.isEmpty ? "25016460" : deviceId

        burstSyncTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.cloudService.sendCommand(deviceKey: keyToUse, token: token, command: command)
                guard !Task.isCancelled else { return }
                
                let delays: [UInt64] = [1_500_000_000, 2_000_000_000, 2_500_000_000]
                for delay in delays {
                    guard !Task.isCancelled else { break }
                    try await Task.sleep(nanoseconds: delay)
                    guard !Task.isCancelled else { break }
                    await MainActor.run { self.refreshData() }
                    let confirmed = await MainActor.run { self.pendingTargetTemp == nil && self.pendingKanal1Speed == nil }
                    if confirmed {
                        break
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run { self.isSyncing = false }
            } catch {
                guard !Task.isCancelled else { return }
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
        if let savedIP = UserDefaults.standard.string(forKey: "stove_local_ip"), !savedIP.isEmpty {
            self.stoveLocalIP = savedIP
        }
        self.loadDiagnostics()
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
            // Hürde 5.2: Begrenzung auf 48 Stunden (2 Tage) für schnellen Start und geringe RAM-Last
            let (roomPoints, exhaustPoints) = try await haService.fetchTemperatureHistory(days: 2)
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
