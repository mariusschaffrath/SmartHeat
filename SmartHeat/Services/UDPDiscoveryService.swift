import Foundation
import Network
import Combine

@MainActor
class UDPDiscoveryService: ObservableObject {
    private var connections: [NWConnection] = []
    private var listener: NWListener?
    private var browser: NWBrowser?
    nonisolated private let queue = DispatchQueue(label: "UDPDiscoveryQueue", attributes: .concurrent)
    
    @Published var discoveredIP: String?
    @Published var isScanning = false
    @Published var logs: String = ""
    
    func discoverStove() {
        guard !isScanning else { return }
        self.isScanning = true
        self.logs = ""
        self.addLog("Suche Ofen im Netzwerk...")
        
        setupListener()
        setupBonjourBrowser()
        sendBroadcast()
        scanSubnet()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.isScanning {
                    self.addLog("Suche abgeschlossen.")
                    self.isScanning = false
                    self.stopDiscovery()
                }
            }
        }
    }
    
    private func scanSubnet() {
        guard let localIP = getLocalIPAddress() else { return }
        let components = localIP.components(separatedBy: ".")
        guard components.count == 4 else { return }
        let baseIP = components.prefix(3).joined(separator: ".")
        
        // Wir scannen gezielt nur die wahrscheinlichsten Ports
        let targetPorts: [UInt16] = [80, 81]
        
        for i in 1...50 {
            let targetIP = "\(baseIP).\(i)"
            if targetIP == localIP { continue }
            
            for portValue in targetPorts {
                let host = NWEndpoint.Host(targetIP)
                let port = NWEndpoint.Port(rawValue: portValue)!
                let connection = NWConnection(host: host, port: port, using: .tcp)
                
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    if state == .ready {
                        Task { @MainActor in
                            if self.isScanning {
                                self.addLog("Ofen lokal gefunden: \(targetIP)")
                                self.discoveredIP = targetIP
                                self.isScanning = false
                                self.stopDiscovery()
                            }
                        }
                    } else if case .failed = state {
                        connection.cancel()
                    }
                }
                connection.start(queue: queue)
                self.connections.append(connection)
            }
        }
    }
    
    private func setupBonjourBrowser() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_http._tcp", domain: nil)
        browser = NWBrowser(for: descriptor, using: .init())
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            Task { @MainActor in
                for result in results {
                    if result.endpoint.debugDescription.lowercased().contains("esp") || 
                       result.endpoint.debugDescription.lowercased().contains("4heat") {
                        if case let .hostPort(host, _) = result.endpoint {
                            let ip = self.formatHost(host)
                            self.addLog("Bonjour Fund: \(ip)")
                            self.discoveredIP = ip
                            self.isScanning = false
                            self.stopDiscovery()
                        }
                    }
                }
            }
        }
        browser?.start(queue: queue)
    }
    
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                if let interface = ptr?.pointee, interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    if String(cString: interface.ifa_name) == "en0" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
    
    nonisolated private func formatHost(_ host: NWEndpoint.Host) -> String {
        if case let .ipv4(address) = host { return "\(address)" }
        if case let .name(name, _) = host { return name.components(separatedBy: ".").first ?? name }
        return host.debugDescription
    }
    
    private func sendBroadcast() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let connection = NWConnection(host: "255.255.255.255", port: 6666, using: params)
        connection.stateUpdateHandler = { [weak self] state in
            if state == .ready {
                connection.send(content: "4HEAT_DISCOVER".data(using: .utf8), completion: .contentProcessed({ _ in }))
            }
        }
        connection.start(queue: queue)
        self.connections.append(connection)
    }
    
    private func setupListener() {
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: 5555)
            self.listener = listener
            let dq = self.queue
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: dq)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, _, _ in
                    if let data = data, let response = String(data: data, encoding: .utf8) {
                        Task { @MainActor in
                            if let ip = self?.extractIP(from: response, connection: connection) {
                                self?.addLog("Antwort von \(ip)")
                                self?.discoveredIP = ip
                                self?.isScanning = false
                                self?.stopDiscovery()
                            }
                        }
                    }
                }
            }
            listener.start(queue: queue)
        } catch { }
    }
    
    nonisolated private func extractIP(from response: String, connection: NWConnection) -> String? {
        let parts = response.components(separatedBy: CharacterSet(charactersIn: ",; "))
        for part in parts {
            if part.contains(".") && part.split(separator: ".").count == 4 { return part }
        }
        return self.formatHost(connection.endpoint.extractHost() ?? .ipv4(.any))
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        self.logs += "[\(timestamp)] \(message)\n"
    }
    
    func stopDiscovery() {
        for conn in connections { conn.cancel() }
        connections.removeAll()
        listener?.cancel()
        browser?.cancel()
    }
}

extension NWEndpoint {
    func extractHost() -> NWEndpoint.Host? {
        if case let .hostPort(host, _) = self { return host }
        return nil
    }
}
