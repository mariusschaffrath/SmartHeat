import Foundation
import Network
import Combine

@MainActor
class StoveSocketService: ObservableObject {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "StoveSocketQueue")
    
    @Published var isConnected = false
    @Published var responseMessage: String = ""
    @Published var activeError: StoveError?
    
    private var dataBuffer = Data()
    
    func connect(host: String, port: UInt16 = 80) {
        disconnect()
        self.activeError = nil
        
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        
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
                default:
                    break
                }
            }
        }
        
        connection?.start(queue: queue)
    }
    
    func sendCommand(_ command: StoveCommand) {
        guard isConnected, let connection = connection else { return }
        
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
        
        guard let data = payload.data(using: .utf8) else { return }
        print("WLAN SEND: \(payload.trimmingCharacters(in: .whitespacesAndNewlines))")
        
        connection.send(content: data, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                Task { @MainActor in
                    print("WLAN SEND ERROR: \(error.localizedDescription)")
                    self?.activeError = StoveError.commandFailed(command: raw, detail: error.localizedDescription)
                }
            }
        }))
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
                } else {
                    self.receiveResponse()
                }
            }
        }
    }
    
    private func processBuffer() {
        guard let string = String(data: dataBuffer, encoding: .utf8) else { return }
        
        if let firstBracket = string.firstIndex(of: "["),
           let lastBracket = string.lastIndex(of: "]"),
           firstBracket < lastBracket {
            
            let fullPacket = String(string[firstBracket...lastBracket])
            print("WLAN RECV: \(fullPacket)")
            self.responseMessage = fullPacket
            
            let remainingIndex = string.index(after: lastBracket)
            let remainingString = String(string[remainingIndex...])
            self.dataBuffer = Data(remainingString.utf8)
        }
    }
    
    func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        isConnected = false
        dataBuffer.removeAll()
    }
}
