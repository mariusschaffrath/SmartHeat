import Foundation
import Combine

@MainActor
class StoveViewModel: ObservableObject {
    @Published var bleManager = BLEManager()
    @Published var socketService = StoveSocketService()
    @Published var cloudService = CloudService()
    @Published var discoveryService = UDPDiscoveryService()
    @Published var authService = AuthService()
    
    @Published var stoveStatus: String = "Standby"
    @Published var currentTemp: Double = 0.0
    @Published var waterTemp: Double = 0.0
    @Published var targetTemp: Double = 22.0
    @Published var exhaustTemp: Double = 0.0
    @Published var waterPressure: Double = 0.0
    
    @Published var isTargetLocked: Bool = true
    @Published var activeError: StoveError?
    
    private let interactionLockDuration: TimeInterval = 25.0
    
    @Published var isSimulatorMode: Bool = UserDefaults.standard.bool(forKey: "is_simulator_mode") {
        didSet {
            UserDefaults.standard.set(isSimulatorMode, forKey: "is_simulator_mode")
            configureEndpoints()
        }
    }
    
    @Published var isWaterStove: Bool = UserDefaults.standard.bool(forKey: "is_water_stove") {
        didSet { UserDefaults.standard.set(isWaterStove, forKey: "is_water_stove") }
    }
    
    // Numeric Serial Number (for info)
    @Published var deviceId: String = UserDefaults.standard.string(forKey: "saved_device_id") ?? "25016460" {
        didSet { UserDefaults.standard.set(deviceId, forKey: "saved_device_id") }
    }
    
    // 36-character DeviceKey GUID (required for Cloud API REST calls)
    @Published var cloudGuid: String = UserDefaults.standard.string(forKey: "saved_cloud_guid") ?? "" {
        didSet { UserDefaults.standard.set(cloudGuid, forKey: "saved_cloud_guid") }
    }
    
    @Published var lastRawMessage: String = ""
    
    private var lastUserInteraction: Date = Date.distantPast
    private var previousHexArray: [String] = []
    
    func triggerInteractionLock() {
        lastUserInteraction = Date()
    }
    
    private func isInteractionLocked() -> Bool {
        return Date().timeIntervalSince(lastUserInteraction) < interactionLockDuration
    }
    
    @Published var manualIP: String = UserDefaults.standard.string(forKey: "manual_ip") ?? "" {
        didSet { UserDefaults.standard.set(manualIP, forKey: "manual_ip") }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: AnyCancellable?
    
    init() {
        setupSubscriptions()
        loadSavedData()
        configureEndpoints()
        startPolling()
        attemptAutoLogin()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            if self.isSimulatorMode {
                if !self.socketService.isConnected {
                    self.socketService.connect(host: "127.0.0.1", port: 8080)
                }
            } else if !self.socketService.isConnected && !self.manualIP.isEmpty && self.manualIP != "192.168.178.1" {
                self.socketService.connect(host: self.manualIP)
            }
        }
    }
    
    func configureEndpoints() {
        let cloudBase = isSimulatorMode ? "http://127.0.0.1:8000" : "https://wifi4heat.azurewebsites.net"
        authService.setBaseURL(cloudBase)
        cloudService.setBaseURL("\(cloudBase)/api/devices")
        print("CONFIG: Endpunkte gesetzt auf \(cloudBase) (Simulator: \(isSimulatorMode))")
        if isSimulatorMode {
            self.cloudGuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
            if !socketService.isConnected {
                socketService.connect(host: "127.0.0.1", port: 8080)
            }
        }
    }
    
    private func attemptAutoLogin() {
        guard let email = KeychainService.shared.load(key: "cloud_email"),
              let password = KeychainService.shared.load(key: "cloud_password") else { return }
        Task {
            do {
                try await authService.login(email: email, password: password)
                self.updateCloudGuidFromDevices()
            } catch {
                print("Auto-login failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupSubscriptions() {
        discoveryService.$discoveredIP
            .compactMap { $0 }
            .sink { [weak self] ip in self?.socketService.connect(host: ip) }
            .store(in: &cancellables)
            
        socketService.$responseMessage
            .sink { [weak self] msg in
                if !msg.isEmpty {
                    self?.lastRawMessage = "WLAN: \(msg.prefix(50))..."
                    self?.parseStoveResponse(msg)
                }
            }
            .store(in: &cancellables)
            
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
            
        socketService.objectWillChange
            .sink { [weak self] _ in
                self?.forwardErrors()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    private func forwardErrors() {
        if let err = authService.activeError {
            self.activeError = err
        } else if let err = cloudService.activeError {
            self.activeError = err
        } else if let err = socketService.activeError {
            self.activeError = err
        }
    }
    
    private func updateCloudGuidFromDevices() {
        if let first = authService.devices.first, !first.id.isEmpty {
            if self.cloudGuid != first.id {
                self.cloudGuid = first.id
                print("CONFIG: GUID \(first.id) aus Cloud-Geräten übernommen.")
            }
        }
    }
    
    private func startPolling() {
        pollTimer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshData() }
    }
    
    func refreshData() {
        if socketService.isConnected {
            socketService.sendCommand(.selAll)
        } else if authService.isAuthenticated, let token = authService.token {
            let keyToUse = cloudGuid.isEmpty ? deviceId : cloudGuid
            guard !keyToUse.isEmpty else { return }
            
            Task {
                do {
                    if let data = try await cloudService.fetchStoveUpdate(deviceKey: keyToUse, token: token) {
                        if let guid = data.deviceKey, !guid.isEmpty, guid != self.cloudGuid {
                            self.cloudGuid = guid
                        }
                        
                        if let currentArray = data.Values {
                            sniffChanges(newArray: currentArray)
                        }
                        
                        if let mapped = data.getMappedValues() {
                            self.currentTemp = mapped.room
                            self.exhaustTemp = mapped.exhaust
                            
                            if !isInteractionLocked() {
                                self.targetTemp = mapped.target
                            }
                            
                            self.waterTemp = mapped.water
                            self.waterPressure = mapped.pressure
                            updateStatusLabel(mapped.status)
                            self.lastRawMessage = "Cloud Live-Daten empfangen."
                        } else if let vals = data.values ?? data.data {
                            if let r = vals["I30006"] ?? vals["30006"], let rv = Double(r) { self.currentTemp = rv / 10.0 }
                            if !isInteractionLocked() {
                                if let t = vals["A20493"] ?? vals["20493"], let tv = Double(t) {
                                    self.targetTemp = tv / 10.0
                                }
                            }
                        }
                    } else {
                        // Cloud returned empty array for this user -> Trigger local WLAN discovery fallback
                        if !self.discoveryService.isScanning && !self.socketService.isConnected {
                            self.lastRawMessage = "Keine Cloud-Daten. Suche Ofen im WLAN..."
                            self.discoveryService.discoverStove()
                        }
                    }
                } catch {
                    print("Cloud Refresh Error: \(error)")
                }
            }
        }
    }
    
    private func parseStoveResponse(_ msg: String) {
        self.lastRawMessage = msg
        
        // 1. Try JSON Array format ["SEL","0",["hex1","hex2",...]]
        if let data = msg.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any],
           jsonArray.count >= 3,
           let hexStrings = jsonArray[2] as? [String] {
            
            let mockData = CloudStoveData(deviceKey: nil, values: nil, Values: hexStrings, data: nil)
            if let mapped = mockData.getMappedValues() {
                self.currentTemp = mapped.room
                self.exhaustTemp = mapped.exhaust
                if !isInteractionLocked() {
                    self.targetTemp = mapped.target
                }
                self.waterTemp = mapped.water
                self.waterPressure = mapped.pressure
                updateStatusLabel(mapped.status)
                return
            }
        }
        
        // 2. Legacy key-value parser fallback
        let components = msg.components(separatedBy: CharacterSet(charactersIn: "[]\", "))
            .filter { $0.count >= 6 }
        
        for part in components {
            if part != "SEC" && part != "SEL" && part != "1" && part != "0" {
                updateValueFromID(part)
            }
        }
    }
    
    private func updateValueFromID(_ part: String) {
        guard part.count >= 6 else { return }
        
        let id = String(part.prefix(6))
        let rawVal = String(part.dropFirst(6))
        
        guard let val = Double(rawVal) else { return }
        let numericID = String(id.dropFirst())
        
        switch numericID {
        case "30001": updateStatusLabel(Int(val))
        case "30005": self.exhaustTemp = val / 10.0
        case "30006": self.currentTemp = val / 10.0
        case "30017": self.waterTemp = val / 10.0
        case "30020": self.waterPressure = val / 1000.0
        case "20493", "20180", "2018": 
            if !isInteractionLocked() {
                self.targetTemp = val / 10.0
            }
        default: break
        }
    }
    
    private func updateStatusLabel(_ code: Int) {
        switch code {
        case 0: stoveStatus = "AUS"
        case 1: stoveStatus = "Check Up"
        case 2, 4, 30, 31, 32, 33, 34: stoveStatus = "Zündung"
        case 3: stoveStatus = "Stabilisierung"
        case 5: stoveStatus = "Betrieb"
        case 6: stoveStatus = "Modulation"
        case 7: stoveStatus = "Reinigung"
        case 8: stoveStatus = "Sicherheit"
        case 9: stoveStatus = "Blockierung"
        case 10: stoveStatus = "Wiederzündung"
        case 11: stoveStatus = "Standby"
        case 13: stoveStatus = "Betrieb M"
        default: stoveStatus = "Aktiv (\(code))"
        }
    }
    
    func turnOn() { 
        triggerInteractionLock()
        sendUniversal(command: .turnOn) 
    }
    
    func turnOff() { 
        triggerInteractionLock()
        sendUniversal(command: .turnOff) 
    }
    
    func setTemperature(_ value: Double) {
        guard !isTargetLocked else { return }
        triggerInteractionLock()
        targetTemp = value
        sendUniversal(command: StoveCommand.writeParameter(id: "20493", value: Int(value * 10))) 
    }
    
    private func sendUniversal(command: StoveCommand) {
        if socketService.isConnected {
            socketService.sendCommand(command)
        } else if authService.isAuthenticated, let token = authService.token {
            var keyToUse = cloudGuid
            if keyToUse.isEmpty {
                if let firstDevice = authService.devices.first {
                    keyToUse = firstDevice.id
                    self.cloudGuid = keyToUse
                }
            }
            if keyToUse.isEmpty { keyToUse = deviceId }

            guard !keyToUse.isEmpty else {
                let err = StoveError.noDeviceFound()
                self.activeError = err
                return
            }

            Task {
                do {
                    try await cloudService.sendCommand(deviceKey: keyToUse, token: token, command: command)
                } catch {
                    print("Send command failed: \(error.localizedDescription)")
                }
            }
        } else {
            let err = StoveError.cloudNetworkError(message: "Keine aktive Verbindung zum Ofen.")
            self.activeError = err
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
        socketService.activeError = nil
        self.activeError = nil
        KeychainService.shared.remove(key: "cloud_email")
        KeychainService.shared.remove(key: "cloud_password")
    }
    
    private func sniffChanges(newArray: [String]) {
        guard !previousHexArray.isEmpty else {
            previousHexArray = newArray
            return
        }
        
        for (i, newValue) in newArray.enumerated() {
            if i < previousHexArray.count {
                let oldValue = previousHexArray[i]
                if newValue != oldValue {
                    print("SNIFFER: Änderung in Index \(i)!")
                    print("  ALT: \(oldValue)")
                    print("  NEU: \(newValue)")
                    self.lastRawMessage = "Sniff: \(i) geändert"
                }
            }
        }
        previousHexArray = newArray
    }
}
