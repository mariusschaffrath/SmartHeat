import Foundation
import Combine

public struct CloudStoveData: Codable {
    public let deviceKey: String?
    public let values: [String: String]? // Fallback
    public let Values: [String]?        // Main 4Heat Hex array format
    public let data: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case deviceKey = "DeviceKey"
        case values, Values, data
    }
    
    public func getMappedValues() -> (room: Double, exhaust: Double, target: Double, water: Double, pressure: Double, status: Int)? {
        guard let array = Values, !array.isEmpty else { return nil }
        
        var room: Double = 0
        var exhaust: Double = 0
        var target: Double = 0
        var water: Double = 0
        var pressure: Double = 0
        var status: Int = 0
        
        // Status from Block 0
        let mainValues = array[0]
        if mainValues.count >= 12 {
            status = Int(extractHex(from: mainValues, start: 10, length: 2) ?? "0", radix: 16) ?? 0
        }
        
        for block in array {
            if block.hasPrefix("12ffff") {
                // Exhaust sensor (30005) - Direct integer °C
                if let rawHex = extractHex(from: block, start: 6, length: 4), let raw = Int(rawHex, radix: 16) {
                    exhaust = Double(raw)
                }
            } else if block.hasPrefix("12fff7") {
                // Room temp sensor (30006) - Tenths of °C
                if let rawHex = extractHex(from: block, start: 6, length: 4), let raw = Int(rawHex, radix: 16) {
                    room = Double(raw) / 10.0
                }
            } else if block.hasPrefix("0e") {
                let id = extractHex(from: block, start: 2, length: 4) ?? ""
                let rawVal = Int(extractHex(from: block, start: 6, length: 4) ?? "0", radix: 16) ?? 0
                
                switch id {
                case "01ed": // Room Target (20493)
                    target = Double(rawVal) / 10.0
                case "0180": // Water Target (20180)
                    water = Double(rawVal) / 10.0
                default: break
                }
            }
        }
        
        // Fallback for room if block 12fff7 wasn't present
        if room == 0 && mainValues.count >= 24 {
            room = Double(Int(extractHex(from: mainValues, start: 20, length: 4) ?? "0", radix: 16) ?? 0) / 10.0
        }
        
        return (room, exhaust, target, water, pressure, status)
    }
    
    private func extractHex(from hex: String, start: Int, length: Int) -> String? {
        guard start + length <= hex.count else { return nil }
        let startIndex = hex.index(hex.startIndex, offsetBy: start)
        let endIndex = hex.index(startIndex, offsetBy: length)
        return String(hex[startIndex..<endIndex])
    }
}

@MainActor
class CloudService: ObservableObject {
    @Published var lastCloudResponse: String = ""
    @Published var activeError: StoveError?
    
    private(set) public var baseURL = "https://wifi4heat.azurewebsites.net/api/devices"
    
    func setBaseURL(_ url: String) {
        self.baseURL = url
    }
    
    /// Fetches live stove telemetry from Cloud using official Dielle REST endpoints (/RealTime?id= and /Summary?ids=)
    func fetchStoveUpdate(deviceKey: String, token: String) async throws -> CloudStoveData? {
        self.activeError = nil
        
        // Exact endpoints reverse-engineered from official Dielle app (com.ionicframework.dielle389999)
        let endpoints = [
            "/RealTime?id=\(deviceKey)",
            "/Summary?ids=\(deviceKey)",
            "/Summary?id=\(deviceKey)"
        ]
        
        for ep in endpoints {
            guard let url = URL(string: "\(baseURL)\(ep)") else { continue }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 8.0
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                
                if statusCode == 200 {
                    if let jsonString = String(data: data, encoding: .utf8), jsonString != "[]" && !jsonString.isEmpty {
                        self.lastCloudResponse = jsonString
                        
                        if let decoded = try? JSONDecoder().decode(CloudStoveData.self, from: data) {
                            return decoded
                        } else if let decodedArray = try? JSONDecoder().decode([CloudStoveData].self, from: data), let first = decodedArray.first {
                            return first
                        }
                    }
                } else if statusCode == 401 {
                    print("DEBUG: Cloud endpoint returned 401 for \(url).")
                    continue
                }
            } catch let err as StoveError {
                throw err
            } catch {
                continue
            }
        }
        
        return nil
    }
    
    /// Sends a command to the stove via Cloud API (using official Dielle payload format { "id": "...", "comando": ["1", "..."] })
    func sendCommand(deviceKey: String, token: String, command: StoveCommand) async throws {
        self.activeError = nil
        
        let url = URL(string: "\(baseURL)/command")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        // Exact payload format from official Dielle app controllers.js
        let body: [String: Any] = [
            "id": deviceKey,
            "comando": ["1", command.rawString]
        ]
        
        print("CLOUD SENDING to ID \(deviceKey): \(command.rawString)")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            if statusCode == 200 {
                if let respStr = String(data: data, encoding: .utf8) {
                    print("CLOUD RESPONSE (\(statusCode)): \(respStr)")
                }
            } else if statusCode == 401 {
                let err = StoveError.sessionExpired()
                self.activeError = err
                throw err
            } else {
                let err = StoveError.commandFailed(command: command.rawString, detail: "Cloud antwortete mit Status \(statusCode).")
                self.activeError = err
                throw err
            }
        } catch let err as StoveError {
            throw err
        } catch {
            let err = StoveError.commandFailed(command: command.rawString, detail: error.localizedDescription)
            self.activeError = err
            throw err
        }
    }
}
