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
        
        // Block 0: Status & Temps
        let mainValues = array[0]
        status = Int(extractHex(from: mainValues, start: 10, length: 2) ?? "0", radix: 16) ?? 0
        exhaust = Double(Int(extractHex(from: mainValues, start: 12, length: 4) ?? "0", radix: 16) ?? 0) / 10.0
        room = Double(Int(extractHex(from: mainValues, start: 20, length: 4) ?? "0", radix: 16) ?? 0) / 10.0
        
        // Scan blocks for target registers
        for block in array {
            if block.hasPrefix("0e") {
                let id = extractHex(from: block, start: 2, length: 4) ?? ""
                let rawVal = Int(extractHex(from: block, start: 6, length: 4) ?? "0", radix: 16) ?? 0
                
                switch id {
                case "01ed": // Room Target (493)
                    target = Double(rawVal) / 10.0
                case "0180": // Water Target (384)
                    water = Double(rawVal) / 10.0
                default: break
                }
            }
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
    
    /// Fetches live stove telemetry from Cloud using the 36-character DeviceKey GUID
    func fetchStoveUpdate(deviceKey: String, token: String) async throws -> CloudStoveData? {
        self.activeError = nil
        
        // Correct 4Heat Azure REST endpoint: /Summary?id={deviceKey}
        let endpoints = ["/Summary?id=\(deviceKey)"]
        
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
                    if let jsonString = String(data: data, encoding: .utf8), jsonString != "[]" {
                        self.lastCloudResponse = jsonString
                        
                        if let decoded = try? JSONDecoder().decode(CloudStoveData.self, from: data) {
                            return decoded
                        } else if let decodedArray = try? JSONDecoder().decode([CloudStoveData].self, from: data), let first = decodedArray.first {
                            return first
                        }
                    }
                } else if statusCode == 401 {
                    print("DEBUG: Cloud endpoint returned 401 for \(url). Trying fallback endpoints...")
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
    
    /// Sends a command to the stove via Cloud API
    func sendCommand(deviceKey: String, token: String, command: StoveCommand) async throws {
        self.activeError = nil
        
        let url = URL(string: "\(baseURL)/command")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        let body: [String: Any] = [
            "DeviceId": deviceKey,
            "Comando": ["1", command.rawString]
        ]
        
        print("CLOUD SENDING to GUID \(deviceKey): \(command.rawString)")
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
