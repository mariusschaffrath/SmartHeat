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
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(throwing: NSError(domain: "HardwareChrono", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ungültiger Port"]))
                return
            }
            
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.connectionTimeout = 5
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)
            let queue = DispatchQueue(label: "HardwareChronoQueue")
            
            var didResume = false
            
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let cmd = "[\"CCG\",\"0\"]\n"
                    guard let data = cmd.data(using: .utf8) else {
                        if !didResume {
                            didResume = true
                            continuation.resume(throwing: NSError(domain: "HardwareChrono", code: -2, userInfo: [NSLocalizedDescriptionKey: "Fehler beim Erstellen der Anfrage"]))
                            conn.cancel()
                        }
                        return
                    }
                    
                    conn.send(content: data, completion: .contentProcessed({ error in
                        if let error = error {
                            if !didResume {
                                didResume = true
                                continuation.resume(throwing: error)
                                conn.cancel()
                            }
                            return
                        }
                        
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { respData, _, _, respError in
                            conn.cancel()
                            if let respError = respError {
                                if !didResume {
                                    didResume = true
                                    continuation.resume(throwing: respError)
                                }
                                return
                            }
                            
                            guard let respData = respData,
                                  let text = String(data: respData, encoding: .utf8) else {
                                if !didResume {
                                    didResume = true
                                    continuation.resume(throwing: NSError(domain: "HardwareChrono", code: -3, userInfo: [NSLocalizedDescriptionKey: "Keine Daten vom Ofen erhalten"]))
                                }
                                return
                            }
                            
                            // Parse JSON array
                            if let jsonData = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
                               let array = try? JSONSerialization.jsonObject(with: jsonData) as? [String],
                               let plan = HardwareChronoPlan.parseFromResponse(array) {
                                Task { @MainActor in
                                    self.chronoPlan = plan
                                    self.lastSyncDate = Date()
                                    self.saveToCache()
                                }
                                if !didResume {
                                    didResume = true
                                    continuation.resume(returning: plan)
                                }
                            } else {
                                if !didResume {
                                    didResume = true
                                    continuation.resume(throwing: NSError(domain: "HardwareChrono", code: -4, userInfo: [NSLocalizedDescriptionKey: "Ungültige Antwort der Platine"]))
                                }
                            }
                        }
                    }))
                    
                case .failed(let err):
                    if !didResume {
                        didResume = true
                        continuation.resume(throwing: err)
                        conn.cancel()
                    }
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
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(throwing: NSError(domain: "HardwareChrono", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ungültiger Port"]))
                return
            }
            
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.connectionTimeout = 5
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)
            let queue = DispatchQueue(label: "HardwareChronoQueue")
            var didResume = false
            
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let data = ccsPayload.data(using: .utf8) else {
                        if !didResume {
                            didResume = true
                            continuation.resume(throwing: NSError(domain: "HardwareChrono", code: -2, userInfo: [NSLocalizedDescriptionKey: "Fehler beim Kodieren des Zeitplans"]))
                            conn.cancel()
                        }
                        return
                    }
                    
                    conn.send(content: data, completion: .contentProcessed({ error in
                        if let error = error {
                            if !didResume {
                                didResume = true
                                continuation.resume(throwing: error)
                                conn.cancel()
                            }
                            return
                        }
                        
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { respData, _, _, respError in
                            conn.cancel()
                            if let respError = respError {
                                if !didResume {
                                    didResume = true
                                    continuation.resume(throwing: respError)
                                }
                                return
                            }
                            
                            guard let respData = respData,
                                  let text = String(data: respData, encoding: .utf8) else {
                                if !didResume {
                                    didResume = true
                                    continuation.resume(returning: true)
                                }
                                return
                            }
                            
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
                            if !didResume {
                                didResume = true
                                continuation.resume(returning: isSuccess)
                            }
                        }
                    }))
                    
                case .failed(let err):
                    if !didResume {
                        didResume = true
                        continuation.resume(throwing: err)
                        conn.cancel()
                    }
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
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(throwing: NSError(domain: "HardwareChrono", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ungültiger Port"]))
                return
            }
            
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.connectionTimeout = 5
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)
            let queue = DispatchQueue(label: "HardwareChronoQueue")
            var didResume = false
            
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let data = payload.data(using: .utf8) else {
                        if !didResume {
                            didResume = true
                            continuation.resume(throwing: NSError(domain: "HardwareChrono", code: -2, userInfo: [NSLocalizedDescriptionKey: "Fehler beim Kodieren"]))
                            conn.cancel()
                        }
                        return
                    }
                    
                    conn.send(content: data, completion: .contentProcessed({ error in
                        conn.cancel()
                        if let error = error {
                            if !didResume {
                                didResume = true
                                continuation.resume(throwing: error)
                            }
                        } else {
                            Task { @MainActor in
                                self.chronoPlan.isGloballyEnabled = enabled
                                self.saveToCache()
                            }
                            if !didResume {
                                didResume = true
                                continuation.resume(returning: true)
                            }
                        }
                    }))
                    
                case .failed(let err):
                    if !didResume {
                        didResume = true
                        continuation.resume(throwing: err)
                        conn.cancel()
                    }
                default:
                    break
                }
            }
            
            conn.start(queue: queue)
        }
    }
}
