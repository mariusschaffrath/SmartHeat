//
//  HomeAssistantService.swift
//  SmartHeat
//
//  24/7 Telemetry History & Pellet Tank State Provider via Home Assistant REST API.
//  Bridges Home Assistant's 24/7 Recorder database (192.168.178.131:8123) with SmartHeat.
//

import Foundation
import SwiftUI
import Combine

public struct HAEntityHistoryItem: Codable {
    public let entityId: String
    public let state: String
    public let lastUpdated: String
    public let lastChanged: String?
    
    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state
        case lastUpdated = "last_updated"
        case lastChanged = "last_changed"
    }
}

public struct HAStateResponse: Codable {
    public let entityId: String
    public let state: String
    public let attributes: [String: AnyCodable]?
    
    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state
        case attributes
    }
}

public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let strVal = try? container.decode(String.self) {
            value = strVal
        } else {
            value = ""
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let val = value as? Double {
            try container.encode(val)
        } else if let val = value as? Int {
            try container.encode(val)
        } else if let val = value as? Bool {
            try container.encode(val)
        } else {
            try container.encode(String(describing: value))
        }
    }
}

@MainActor
public class HomeAssistantService: ObservableObject {
    public static let shared = HomeAssistantService()
    
    // MARK: - Configuration Keys
    private let urlKey = "ha_server_url"
    private let tokenKey = "ha_access_token"
    private let enabledKey = "ha_sync_enabled"
    private let roomEntityKey = "ha_room_entity_id"
    private let exhaustEntityKey = "ha_exhaust_entity_id"
    private let pelletEntityKey = "ha_pellet_entity_id"
    
    // MARK: - Published Properties
    @Published public var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: urlKey) }
    }
    @Published public var accessToken: String {
        didSet { UserDefaults.standard.set(accessToken, forKey: tokenKey) }
    }
    @Published public var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }
    
    @Published public var roomEntityId: String {
        didSet { UserDefaults.standard.set(roomEntityId, forKey: roomEntityKey) }
    }
    @Published public var exhaustEntityId: String {
        didSet { UserDefaults.standard.set(exhaustEntityId, forKey: exhaustEntityKey) }
    }
    @Published public var pelletEntityId: String {
        didSet { UserDefaults.standard.set(pelletEntityId, forKey: pelletEntityKey) }
    }
    
    @Published public var isConnected: Bool = false
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncDate: Date? = nil
    @Published public var statusMessage: String = "Nicht verbunden"
    @Published public var lastLoadedPointsCount: Int = 0
    
    private let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private let isoFallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    // MARK: - Initialization
    public init() {
        self.serverURL = UserDefaults.standard.string(forKey: urlKey) ?? "http://192.168.178.131:8123"
        self.accessToken = UserDefaults.standard.string(forKey: tokenKey) ?? ""
        self.isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        self.roomEntityId = UserDefaults.standard.string(forKey: roomEntityKey) ?? "sensor.smartheat_raumtemperatur"
        self.exhaustEntityId = UserDefaults.standard.string(forKey: exhaustEntityKey) ?? "sensor.smartheat_abgastemperatur"
        self.pelletEntityId = UserDefaults.standard.string(forKey: pelletEntityKey) ?? "sensor.smartheat_pellet_vorrat"
    }
    
    // MARK: - API Helpers
    private func cleanURL(_ path: String) -> URL? {
        let base = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)\(path)")
    }
    
    private func createRequest(url: URL, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if !accessToken.isEmpty {
            req.setValue("Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 8.0
        return req
    }
    
    // MARK: - Connection Check
    public func testConnection() async -> Bool {
        guard let url = cleanURL("/api/") else {
            self.statusMessage = "Ungültige Server-URL"
            self.isConnected = false
            return false
        }
        
        let req = createRequest(url: url)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                self.statusMessage = "Keine HTTP-Antwort"
                self.isConnected = false
                return false
            }
            
            if http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["message"] as? String, msg.contains("API running") {
                    self.isConnected = true
                    self.statusMessage = "Verbunden mit Home Assistant ✓"
                    return true
                }
                self.isConnected = true
                self.statusMessage = "Verbunden ✓"
                return true
            } else if http.statusCode == 401 {
                self.isConnected = false
                self.statusMessage = "Authentifizierung fehlgeschlagen (Token ungültig)"
                return false
            } else {
                self.isConnected = false
                self.statusMessage = "Server antwortete mit Status \(http.statusCode)"
                return false
            }
        } catch {
            self.isConnected = false
            self.statusMessage = "Verbindungsfehler: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - Fetch 24/7 Temperature History
    public func fetchTemperatureHistory(days: Int = 30) async throws -> (room: [TemperaturePoint], exhaust: [TemperaturePoint]) {
        guard isEnabled, !accessToken.isEmpty else {
            throw NSError(domain: "SmartHeat", code: 400, userInfo: [NSLocalizedDescriptionKey: "Home Assistant ist nicht aktiviert oder Token fehlt."])
        }
        
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let isoStart = isoFallbackFormatter.string(from: startDate)
        
        let path = "/api/history/period/\(isoStart)?filter_entity_id=\(roomEntityId),\(exhaustEntityId)"
        guard let url = cleanURL(path) else {
            throw NSError(domain: "SmartHeat", code: 400, userInfo: [NSLocalizedDescriptionKey: "Ungültige History-URL."])
        }
        
        self.isSyncing = true
        defer { self.isSyncing = false }
        
        let req = createRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: req)
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "SmartHeat", code: code, userInfo: [NSLocalizedDescriptionKey: "Home Assistant API antwortete mit Status \(code)"])
        }
        
        // Response is an array of arrays of HAEntityHistoryItem
        guard let nestedList = try? JSONDecoder().decode([[HAEntityHistoryItem]].self, from: data) else {
            return ([], [])
        }
        
        var roomPoints: [TemperaturePoint] = []
        var exhaustPoints: [TemperaturePoint] = []
        
        for entityList in nestedList {
            for item in entityList {
                guard let tempVal = Double(item.state), tempVal > 0 else { continue }
                let date = isoDateFormatter.date(from: item.lastUpdated) ?? isoFallbackFormatter.date(from: item.lastUpdated)
                guard let validDate = date else { continue }
                
                let pt = TemperaturePoint(date: validDate, temperature: tempVal)
                if item.entityId == self.roomEntityId {
                    roomPoints.append(pt)
                } else if item.entityId == self.exhaustEntityId {
                    exhaustPoints.append(pt)
                }
            }
        }
        
        self.isConnected = true
        self.lastSyncDate = Date()
        self.lastLoadedPointsCount = roomPoints.count + exhaustPoints.count
        self.statusMessage = "\(self.lastLoadedPointsCount) Messpunkte synchronisiert"
        
        return (
            roomPoints.sorted { $0.date < $1.date },
            exhaustPoints.sorted { $0.date < $1.date }
        )
    }
    
    // MARK: - Fetch 24/7 Pellet Tank State
    public func fetchPelletState() async throws -> (levelKg: Double, percent: Double, remainingHours: Double)? {
        guard isEnabled, !accessToken.isEmpty else { return nil }
        
        guard let url = cleanURL("/api/states/\(pelletEntityId)") else { return nil }
        let req = createRequest(url: url)
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let stateStr = json["state"] as? String,
           let kg = Double(stateStr) {
            
            var pct = (kg / 20.0) * 100.0
            var hours = 20.0
            
            if let attrs = json["attributes"] as? [String: Any] {
                if let p = attrs["pellet_percent"] as? Double { pct = p }
                if let h = attrs["pellet_remaining_hours"] as? Double { hours = h }
            }
            return (kg, pct, hours)
        }
        return nil
    }
    
    // MARK: - Remote Pellet Refill Sync
    public func syncRefillToHomeAssistant(isFull: Bool) async {
        guard isEnabled, !accessToken.isEmpty else { return }
        let service = isFull ? "refill_full" : "refill_bag"
        guard let url = cleanURL("/api/services/smartheat/\(service)") else { return }
        
        var req = createRequest(url: url, method: "POST")
        req.httpBody = "{}".data(using: .utf8)
        
        _ = try? await URLSession.shared.data(for: req)
    }
}
