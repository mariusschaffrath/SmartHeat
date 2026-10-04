import Foundation
import Network
import Combine

@MainActor
class StoveSocketService: ObservableObject {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "StoveSocketQueue")
    
    @Published var isConnected = false
    @Published var responseMessage: String = ""
    @Published var lastCommandAck: String = ""
    @Published var latestStoveData: CloudStoveData?
    @Published var activeError: StoveError?
    @Published var currentHost: String = "192.168.178.188"
    @Published var currentPort: UInt16 = 80
    
    let telemetrySubject = PassthroughSubject<CloudStoveData, Never>()
    let commandAckSubject = PassthroughSubject<String, Never>()
    
    private var dataBuffer = Data()
    
    nonisolated deinit {}
    
    func setHost(_ host: String, port: UInt16 = 80) {
        guard host != currentHost || port != currentPort else { return }
        self.currentHost = host
        self.currentPort = port
        if isConnected {
            connect(host: host, port: port)
        }
    }
    
    func connect(host: String, port: UInt16 = 80) {
        if isConnected && currentHost == host && currentPort == port && connection != nil {
            return
        }
        
        disconnect()
        self.currentHost = host
        self.currentPort = port
        self.activeError = nil
        
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            self.activeError = StoveError.socketConnectionFailed(host: host, detail: "Ungültiger Port: \(port)")
            return
        }
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 5
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        
        connection = NWConnection(host: nwHost, port: nwPort, using: params)
        
        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.isConnected = true
                    print("WLAN: Verbunden mit \(host):\(port)")
                    self.receiveResponse()
                case .failed(let error):
                    self.isConnected = false
                    print("WLAN: Verbindungsfehler: \(error.localizedDescription)")
                    self.activeError = StoveError.socketConnectionFailed(host: host, detail: error.localizedDescription)
                case .cancelled:
                    self.isConnected = false
                case .waiting(let error):
                    print("WLAN: Warten auf Netzwerk/Host: \(error.localizedDescription)")
                default:
                    break
                }
            }
        }
        
        connection?.start(queue: queue)
    }
    
    func formatPayload(for command: StoveCommand) -> String {
        let raw = command.rawString
        var payload: String
        
        if raw == "2WL0" || raw == "2WL" {
            payload = "[\"2WL\",\"0\"]"
        } else if raw == "SEL0" || raw == "SEL" {
            payload = "[\"SEL\",\"0\"]"
        } else if raw.hasPrefix("05") || raw.hasPrefix("2WC") {
            // 2ways Write Command (turnOn, turnOff, unlock, writeParameter): ["2WC","1","<hex>"]
            let clean = raw.replacingOccurrences(of: "2WC", with: "")
            payload = "[\"2WC\",\"1\",\"\(clean.isEmpty ? raw : clean)\"]"
        } else if raw.hasPrefix("B") || raw.hasPrefix("J") || raw.hasPrefix("SEC") {
            // Syevo Write & Switch commands require SEC layer: ["SEC","1","<raw>"]
            let clean = raw.replacingOccurrences(of: "SEC", with: "")
            payload = "[\"SEC\",\"1\",\"\(clean.isEmpty ? raw : clean)\"]"
        } else {
            payload = "[\"\(raw)\"]"
        }
        
        // CRITICAL FIX: Append newline delimiter \n required by 4Heat TCP firmware
        if !payload.hasSuffix("\n") {
            payload += "\n"
        }
        return payload
    }
    
    func sendCommand(_ command: StoveCommand) {
        guard isConnected, let connection = connection else { return }
        
        let payload = formatPayload(for: command)
        guard let data = payload.data(using: .utf8) else { return }
        print("WLAN SEND: \(payload.trimmingCharacters(in: .whitespacesAndNewlines))")
        
        connection.send(content: data, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                Task { @MainActor in
                    print("WLAN SEND ERROR: \(error.localizedDescription)")
                    self?.activeError = StoveError.commandFailed(command: command.rawString, detail: error.localizedDescription)
                }
            }
        }))
    }
    
    func sendCommandAsync(_ command: StoveCommand) async throws {
        guard isConnected, let connection = connection else {
            throw StoveError.socketConnectionFailed(host: currentHost, detail: "Keine aktive TCP-Verbindung")
        }
        
        let payload = formatPayload(for: command)
        guard let data = payload.data(using: .utf8) else {
            throw StoveError.commandFailed(command: command.rawString, detail: "Ungültiges UTF-8")
        }
        print("WLAN SEND ASYNC: \(payload.trimmingCharacters(in: .whitespacesAndNewlines))")
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    Task { @MainActor in
                        self?.activeError = StoveError.commandFailed(command: command.rawString, detail: error.localizedDescription)
                    }
                    continuation.resume(throwing: StoveError.commandFailed(command: command.rawString, detail: error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    /// Stellt sicher, dass eine aktive und bereite TCP-Verbindung existiert
    @discardableResult
    func ensureConnected(timeout: TimeInterval = 2.5) async -> Bool {
        if isConnected && connection?.state == .ready {
            return true
        }
        connect(host: currentHost, port: currentPort)
        
        let start = Date()
        while !isConnected {
            if Date().timeIntervalSince(start) >= timeout {
                return false
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms Abfrageintervall
        }
        return isConnected
    }
    
    /// Fragt 2WL-Telemetrie asynchron ab mit Timeout
    func fetchLiveUpdate(timeout: TimeInterval = 3.0) async throws -> CloudStoveData {
        if !isConnected {
            let connected = await ensureConnected(timeout: min(timeout, 2.0))
            guard connected else {
                throw StoveError.socketConnectionFailed(host: currentHost, detail: "Keine aktive TCP-Verbindung zu \(currentHost)")
            }
        }
        
        sendCommand(StoveCommand.poll2Ways)
        
        return try await withThrowingTaskGroup(of: CloudStoveData.self) { group in
            group.addTask { @MainActor in
                for await data in self.telemetrySubject.values {
                    return data
                }
                throw StoveError.socketConnectionFailed(host: self.currentHost, detail: "Stream beendet")
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw StoveError.socketConnectionFailed(host: await self.currentHost, detail: "Socket-Timeout (\(timeout)s)")
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    /// Prüft, ob der lokale Port 80 erreichbar ist (z. B. für Dual-Path Umschaltung)
    func checkReachability(host: String, port: UInt16 = 80, timeout: TimeInterval = 1.5) async -> Bool {
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = Int(timeout)
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        let probe = NWConnection(host: nwHost, port: nwPort, using: params)
        
        return await withCheckedContinuation { continuation in
            var resumed = false
            let resumeOnce: (Bool) -> Void = { val in
                if !resumed {
                    resumed = true
                    probe.cancel()
                    continuation.resume(returning: val)
                }
            }
            
            probe.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce(true)
                case .failed, .cancelled:
                    resumeOnce(false)
                default:
                    break
                }
            }
            probe.start(queue: self.queue)
            
            self.queue.asyncAfter(deadline: .now() + timeout) {
                resumeOnce(false)
            }
        }
    }
    
    private func receiveResponse() {
        guard let connection = connection else { return }
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            Task { @MainActor in
                if let data = data, !data.isEmpty {
                    self.dataBuffer.append(data)
                    self.processBuffer()
                }
                
                if let error = error {
                    if case .posix(let code) = error, code == .ECONNRESET {
                        self.isConnected = false
                    }
                } else if !isComplete {
                    self.receiveResponse()
                } else {
                    self.isConnected = false
                }
            }
        }
    }
    
    /// Verarbeitet Rohdaten aus dem Puffer: sicheres Line-Splitting an \n & Command-Echo Filter
    func processBuffer() {
        // Line-Splitting: Zeilenweise Verarbeitung aller durch \n (0x0A) abgeschlossenen Pakete.
        // Unvollständige Fragmente verbleiben im dataBuffer!
        while let newlineIndex = dataBuffer.firstIndex(of: 0x0A) {
            let lineData = dataBuffer.subdata(in: 0..<newlineIndex)
            dataBuffer.removeSubrange(0...newlineIndex)
            
            guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
                continue
            }
            
            // Hürde 2.4: Filtere Command-Echoes: Antworten oder Echos, die mit ["2WC" beginnen
            // (z. B. ["2WC","1",...]), dürfen nicht als Telemetrie geparst werden!
            if line.hasPrefix("[\"2WC\"") {
                print("WLAN COMMAND ACK/ECHO: \(line)")
                self.lastCommandAck = line
                self.commandAckSubject.send(line)
                continue
            }
            
            // Telemetrie oder sonstige 2WL-Pakete
            if line.hasPrefix("[\"2WL\"") || line.hasPrefix("[") {
                print("WLAN RECV: \(line)")
                self.responseMessage = line
                if let parsed = parseTelemetry(line: line) {
                    self.latestStoveData = parsed
                    self.telemetrySubject.send(parsed)
                }
            }
        }
        
        // Puffer-Sicherheitsgrenze
        if dataBuffer.count > 65536 {
            dataBuffer.removeAll()
        }
    }
    
    /// Helfer für Unit-Tests & direkte Dateneinspeisung
    func processIncomingData(_ data: Data) {
        dataBuffer.append(data)
        processBuffer()
    }
    
    func parseTelemetry(line: String) -> CloudStoveData? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let first = json.first as? String, first == "2WL",
              json.count >= 3 else {
            return nil
        }
        
        var hexBlocks: [String] = []
        for item in json.dropFirst(2) {
            if let str = item as? String {
                hexBlocks.append(str)
            }
        }
        guard !hexBlocks.isEmpty else { return nil }
        return CloudStoveData(deviceKey: nil, isOnline: true, values: nil, Values: hexBlocks, data: nil)
    }
    
    func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        isConnected = false
        dataBuffer.removeAll()
    }
}
