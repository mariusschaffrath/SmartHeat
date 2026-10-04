//
//  HardwareChronoService.swift
//  SmartHeat
//
//  Direct hardware synchronization service communicating with the Dielle / TiEmme
//  motherboard EEPROM via ["CCG","0"] and ["CCS","71",...] socket protocol.
//

import Foundation
import Network
import Combine

/// Thread-safe one-shot continuation wrapper for Swift 6 strict concurrency compliance
private final class SafeContinuation<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<T, Error>
    
    nonisolated init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }
    
    nonisolated func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
    
    nonisolated func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(throwing: error)
    }
}

@MainActor
public class HardwareChronoService: ObservableObject {
    public static let shared = HardwareChronoService()
    
    @Published public var chronoPlan: HardwareChronoPlan
    @Published public var isSyncing: Bool = false
    @Published public var isSaving: Bool = false
    @Published public var lastSyncDate: Date? = nil
    @Published public var activeError: String? = nil
    @Published public var saveSuccess: Bool = false
    
    private let cacheKey = "hardware_chrono_plan_cache"
    
    public init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(HardwareChronoPlan.self, from: data) {
            self.chronoPlan = cached
        } else {
            self.chronoPlan = HardwareChronoPlan()
        }
    }
    
    public func saveToCache() {
        if let encoded = try? JSONEncoder().encode(chronoPlan) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }
    
    // MARK: - Fetch Timetable from Stove Motherboard (CCG)
    public func fetchFromStove(host: String = "192.168.178.188", port: UInt16 = 80) async throws -> HardwareChronoPlan {
        isSyncing = true
        activeError = nil
        defer { isSyncing = false }
        
        return try await withCheckedThrowingContinuation { continuation in
            let safe = SafeContinuation(continuation)
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                safe.resume(throwing: NSError(domain: "HardwareChrono", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ungültiger Port"]))
                return
            }
            
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.connectionTimeout = 5
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)
            let queue = DispatchQueue(label: "HardwareChronoQueue")
            
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let cmd = "[\"CCG\",\"0\"]\n"
                    guard let data = cmd.data(using: .utf8) else {
                        conn.cancel()
                        safe.resume(throwing: NSError(domain: "HardwareChrono", code: -2, userInfo: [NSLocalizedDescriptionKey: "Fehler beim Erstellen der Anfrage"]))
                        return
                    }
                    
                    conn.send(content: data, completion: .contentProcessed({ error in
                        if let error = error {
                            conn.cancel()
                            safe.resume(throwing: error)
                            return
                        }
                        
                        var receivedData = Data()
                        
                        func readNextChunk() {
                            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { respData, _, isComplete, respError in
                                if let respError = respError {
                                    conn.cancel()
                                    safe.resume(throwing: respError)
                                    return
                                }
                                
                                if let respData = respData, !respData.isEmpty {
                                    receivedData.append(respData)
                                }
                                
                                // TCP-Puffer: Chunks aggregieren, bis schließendes ']' empfangen wurde
                                if let text = String(data: receivedData, encoding: .utf8), text.contains("]") {
                                    conn.cancel()
                                    if let startIdx = text.firstIndex(of: "["),
                                       let endIdx = text.lastIndex(of: "]") {
                                        let jsonSubstring = String(text[startIdx...endIdx])
                                        if let jsonData = jsonSubstring.data(using: .utf8),
                                           let array = try? JSONSerialization.jsonObject(with: jsonData) as? [String],
                                           let plan = HardwareChronoPlan.parseFromResponse(array) {
                                            Task { @MainActor in
                                                self.chronoPlan = plan
                                                self.lastSyncDate = Date()
                                                self.saveToCache()
                                            }
                                            safe.resume(returning: plan)
                                            return
                                        }
                                    }
                                    
                                    safe.resume(throwing: NSError(domain: "HardwareChrono", code: -4, userInfo: [NSLocalizedDescriptionKey: "Ungültige Antwort der Platine"]))
                                    return
                                }
                                
                                if isComplete {
                                    conn.cancel()
                                    safe.resume(throwing: NSError(domain: "HardwareChrono", code: -3, userInfo: [NSLocalizedDescriptionKey: "Verbindung geschlossen bevor vollständiges Frame empfangen wurde"]))
                                    return
                                }
                                
                                readNextChunk()
                            }
                        }
                        
                        readNextChunk()
                    }))
                    
                case .failed(let err):
                    conn.cancel()
                    safe.resume(throwing: err)
                default:
                    break
                }
            }
            
            conn.start(queue: queue)
        }
    }
    
    // MARK: - Save Timetable to Stove Motherboard EEPROM (CCS)
    public func saveToStove(plan: HardwareChronoPlan, host: String = "192.168.178.188", port: UInt16 = 80) async throws -> Bool {
        isSaving = true
        saveSuccess = false
        activeError = nil
        defer { isSaving = false }
        
        let ccsPayload = plan.toCCSCommandString()
        
        return try await withCheckedThrowingContinuation { continuation in
            let safe = SafeContinuation(continuation)
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                safe.resume(throwing: NSError(domain: "HardwareChrono", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ungültiger Port"]))
                return
            }
            
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.connectionTimeout = 5
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)
            let queue = DispatchQueue(label: "HardwareChronoQueue")
            
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let data = ccsPayload.data(using: .utf8) else {
                        conn.cancel()
                        safe.resume(throwing: NSError(domain: "HardwareChrono", code: -2, userInfo: [NSLocalizedDescriptionKey: "Fehler beim Kodieren des Zeitplans"]))
                        return
                    }
                    
                    conn.send(content: data, completion: .contentProcessed({ error in
                        if let error = error {
                            conn.cancel()
                            safe.resume(throwing: error)
                            return
                        }
                        
                        var receivedData = Data()
                        
                        func readSaveResponse() {
                            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { respData, _, isComplete, respError in
                                if let respError = respError {
                                    conn.cancel()
                                    safe.resume(throwing: respError)
                                    return
                                }
                                
                                if let respData = respData, !respData.isEmpty {
                                    receivedData.append(respData)
                                }
                                
                                let text = String(data: receivedData, encoding: .utf8) ?? ""
                                if text.contains("]") || isComplete {
                                    conn.cancel()
                                    // Check for error response ["CCS","E",...]
                                    let isSuccess = !text.contains("\"E\"") && !text.contains("ERR")
                                    Task { @MainActor in
                                        if isSuccess {
                                            self.chronoPlan = plan
                                            self.saveSuccess = true
                                            self.lastSyncDate = Date()
                                            self.saveToCache()
                                        } else {
                                            self.activeError = "Platine hat das Speichern abgelehnt: \(text)"
                                        }
                                    }
                                    safe.resume(returning: isSuccess)
                                    return
                                }
                                
                                readSaveResponse()
                            }
                        }
                        
                        readSaveResponse()
                    }))
                    
                case .failed(let err):
                    conn.cancel()
                    safe.resume(throwing: err)
                default:
                    break
                }
            }
            
            conn.start(queue: queue)
        }
    }
    
    // MARK: - Toggle Global Chrono Enable (crono_enb: 05080000 / 05080100)
    public func toggleGlobalEnable(enabled: Bool, host: String = "192.168.178.188", port: UInt16 = 80) async throws -> Bool {
        let cmdHex = enabled ? "05080000" : "05080100"
        let payload = "[\"2WC\",\"1\",\"\(cmdHex)\"]\n"
        
        return try await withCheckedThrowingContinuation { continuation in
            let safe = SafeContinuation(continuation)
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                safe.resume(throwing: NSError(domain: "HardwareChrono", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ungültiger Port"]))
                return
            }
            
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.connectionTimeout = 5
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)
            let queue = DispatchQueue(label: "HardwareChronoQueue")
            
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let data = payload.data(using: .utf8) else {
                        conn.cancel()
                        safe.resume(throwing: NSError(domain: "HardwareChrono", code: -2, userInfo: [NSLocalizedDescriptionKey: "Fehler beim Kodieren"]))
                        return
                    }
                    
                    conn.send(content: data, completion: .contentProcessed({ error in
                        conn.cancel()
                        if let error = error {
                            safe.resume(throwing: error)
                        } else {
                            Task { @MainActor in
                                self.chronoPlan.isGloballyEnabled = enabled
                                self.saveToCache()
                            }
                            safe.resume(returning: true)
                        }
                    }))
                    
                case .failed(let err):
                    conn.cancel()
                    safe.resume(throwing: err)
                default:
                    break
                }
            }
            
            conn.start(queue: queue)
        }
    }
}
