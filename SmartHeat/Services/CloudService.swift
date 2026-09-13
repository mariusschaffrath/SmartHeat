import Foundation
import Combine

public struct CloudStoveData: Codable {
    public let deviceKey: String?
    public let isOnline: Bool?
    public let values: [String: String]? // Fallback
    public let Values: [String]?        // Main 4Heat/Dielle Hex array format
    public let data: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case deviceKey = "DeviceKey"
        case isOnline = "IsOnline"
        case values, Values, data
        case lastMessage = "LastMessageReceived"
    }
    
    public init(deviceKey: String?, isOnline: Bool? = nil, values: [String: String]?, Values: [String]?, data: [String: String]?) {
        self.deviceKey = deviceKey
        self.isOnline = isOnline
        self.values = values
        self.Values = Values
        self.data = data
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deviceKey = try? container.decode(String.self, forKey: .deviceKey)
        self.isOnline = try? container.decode(Bool.self, forKey: .isOnline)
        self.values = try? container.decode([String: String].self, forKey: .values)
        self.data = try? container.decode([String: String].self, forKey: .data)
        
        if let directValues = try? container.decode([String].self, forKey: .Values) {
            self.Values = directValues
        } else if let lmrString = try? container.decode(String.self, forKey: .lastMessage),
                  let lmrData = lmrString.data(using: .utf8),
                  let lmrJson = try? JSONSerialization.jsonObject(with: lmrData) as? [String: Any],
                  let valArray = lmrJson["Values"] as? [String] {
            self.Values = valArray
        } else {
            self.Values = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try? container.encode(deviceKey, forKey: .deviceKey)
        try? container.encode(isOnline, forKey: .isOnline)
        try? container.encode(values, forKey: .values)
        try? container.encode(Values, forKey: .Values)
        try? container.encode(data, forKey: .data)
    }
    
    /// Parses 2ways / syevo hex array matching official Dielle SERVIZI2W logic
    public func getMappedValues() -> (room: Double, exhaust: Double, target: Double, water: Double, pressure: Double, status: Int)? {
        guard let array = Values, !array.isEmpty else { return nil }
        
        var room: Double = 0
        var exhaust: Double = 0
        var target: Double = 0
        var water: Double = 0
        var pressure: Double = 0
        var status: Int = 0
        var powerLevel: Int = 1
        var isWood: Bool = false
        
        for (index, block) in array.enumerated() {
            // 1. Block 0 or prefix "10" (0x10 = 519_MAINVALUES)
            if block.hasPrefix("10") || index == 0 {
                // Status at offset 10..12
                if let stHex = extractHex(from: block, start: 10, length: 2), let st = Int(stHex, radix: 16) {
                    status = st
                    if st == 13 {
                        isWood = true
                    }
                }
                
                // Multiplier (pos_punto) from offset 36..38 (default: 0.1)
                var multTemp: Double = 0.1
                if block.count >= 38, let ppHex = extractHex(from: block, start: 36, length: 2), let pp = Int(ppHex, radix: 16) {
                    switch pp {
                    case 0: multTemp = 1.0
                    case 1: multTemp = 0.1
                    case 2: multTemp = 0.01
                    case 3: multTemp = 0.001
                    default: multTemp = 0.1
                    }
                }
                
                // Room / Main Temp at offset 20..24 (signed Int16)
                if let tpRaw = extractSignedInt16(from: block, start: 20) {
                    if tpRaw != -127 && tpRaw > 0 {
                        room = Double(tpRaw) * multTemp
                    }
                }
                
                // Secondary Temp (exhaust/return) at offset 6..10
                if let tsRaw = extractSignedInt16(from: block, start: 6) {
                    if tsRaw > 0 && exhaust == 0 {
                        exhaust = Double(tsRaw) * multTemp
                    }
                }
            }
            
            // 2. Info Block with prefix "0c81" (state_info_81)
            if block.hasPrefix("0c81") {
                // Power level at offset 14..16
                if let pwrHex = extractHex(from: block, start: 14, length: 2), let pwr = Int(pwrHex, radix: 16) {
                    if pwr >= 1 && pwr <= 5 {
                        powerLevel = pwr
                    } else if pwr == 6 {
                        // Auto modulation
                        powerLevel = (status == 6) ? 1 : 3
                    }
                }
                
                var multTerm: Double = 0.1
                if block.count >= 30, let ppHex = extractHex(from: block, start: 28, length: 2), let pp = Int(ppHex, radix: 16) {
                    switch pp {
                    case 0: multTerm = 1.0
                    case 1: multTerm = 0.1
                    case 2: multTerm = 0.01
                    case 3: multTerm = 0.001
                    default: multTerm = 0.1
                    }
                }
                // Target thermostat at offset 24..28
                if let ttHex = extractHex(from: block, start: 24, length: 4), let rawTt = Int(ttHex, radix: 16), rawTt > 0 {
                    target = Double(rawTt) * multTerm
                }
            }
            
            // 3. Testout sensor blocks (prefix "12")
            if block.hasPrefix("12") {
                let sensorId = extractHex(from: block, start: 2, length: 4)?.lowercased() ?? ""
                var mult: Double = 1.0
                if block.count >= 22, let ppHex = extractHex(from: block, start: 20, length: 2), let pp = Int(ppHex, radix: 16) {
                    switch pp {
                    case 0: mult = 1.0
                    case 1: mult = 0.1
                    case 2: mult = 0.01
                    case 3: mult = 0.001
                    default: mult = 1.0
                    }
                }
                
                if let rawVal = extractSignedInt16(from: block, start: 6) {
                    if sensorId == "ffff" { // Exhaust temp sensor (30005)
                        exhaust = Double(rawVal) * mult
                    } else if sensorId == "fff7" && room == 0 { // Room temp sensor (30006)
                        room = Double(rawVal) * mult
                    }
                }
            }
            
            // 4. Parameter blocks (prefix "0e")
            if block.hasPrefix("0e") {
                let id = extractHex(from: block, start: 2, length: 4)?.lowercased() ?? ""
                var mult: Double = 0.1
                if block.count >= 22, let ppHex = extractHex(from: block, start: 20, length: 2), let pp = Int(ppHex, radix: 16) {
                    switch pp {
                    case 0: mult = 1.0
                    case 1: mult = 0.1
                    case 2: mult = 0.01
                    default: mult = 0.1
                    }
                }
                
                if let rawVal = extractSignedInt16(from: block, start: 6) {
                    switch id {
                    case "01ed": // Room Target (20493)
                        if target == 0 {
                            target = Double(rawVal) * mult
                        }
                    case "0180": // Water Target (20180)
                        water = Double(rawVal) * mult
                    case "016c": // Pellet Flame power setting
                        if rawVal >= 1 && rawVal <= 5 {
                            powerLevel = rawVal
                        }
                    case "016b": // Wood Flame setting
                        if status == 13 || (rawVal > 0 && status != 5 && status != 6) {
                            isWood = true
                        }
                    default: break
                    }
                }
            }
        }
        
        if status == 6 {
            // Modulation is lowest burn level
            powerLevel = 1
        }
        
        return (room, exhaust, target, water, pressure, status, powerLevel, isWood)
    }
    
    private func extractSignedInt16(from hex: String, start: Int) -> Int? {
        guard let hexPart = extractHex(from: hex, start: start, length: 4),
              let unsigned = UInt16(hexPart, radix: 16) else { return nil }
        return Int(Int16(bitPattern: unsigned))
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
    
    /// Convenience helper for decoding an array of hex values directly (e.g. from unit tests)
    public func parseAllValues(_ values: [String]) -> (room: Double, exhaust: Double, target: Double, status: Int)? {
        let data = CloudStoveData(deviceKey: nil, isOnline: nil, values: nil, Values: values, data: nil)
        guard let mapped = data.getMappedValues() else { return nil }
        return (mapped.room, mapped.exhaust, mapped.target, mapped.status)
    }
    
    /// Extended helper returning power level and wood mode as well
    public func parseAllTelemetry(_ values: [String]) -> (room: Double, exhaust: Double, target: Double, status: Int, powerLevel: Int, isWood: Bool)? {
        let data = CloudStoveData(deviceKey: nil, isOnline: nil, values: nil, Values: values, data: nil)
        guard let mapped = data.getMappedValues() else { return nil }
        return (mapped.room, mapped.exhaust, mapped.target, mapped.status, mapped.powerLevel, mapped.isWood)
    }
    
    /// Fetches live stove telemetry from Cloud using official Dielle REST endpoints (/Summary?ids= and /RealTime?id=)
    func fetchStoveUpdate(deviceKey: String, token: String) async throws -> CloudStoveData? {
        self.activeError = nil
        
        // Exact endpoints reverse-engineered from official Dielle app (com.ionicframework.dielle389999)
        let endpoints = [
            "/Summary?ids=\(deviceKey)",
            "/RealTime?id=\(deviceKey)",
            "/Summary?id=\(deviceKey)"
        ]
        
        for ep in endpoints {
            guard let url = URL(string: "\(baseURL)\(ep)") else { continue }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 8.0
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                
                if statusCode == 200 {
                    if let jsonString = String(data: data, encoding: .utf8), jsonString != "[]" && !jsonString.isEmpty {
                        self.lastCloudResponse = jsonString
                        
                        // 1. Direct CloudStoveData decoding
                        if let decoded = try? JSONDecoder().decode(CloudStoveData.self, from: data), decoded.Values != nil {
                            return decoded
                        }
                        
                        // 2. Array of CloudStoveData
                        if let decodedArray = try? JSONDecoder().decode([CloudStoveData].self, from: data),
                           let first = decodedArray.first, first.Values != nil {
                            return first
                        }
                        
                        // 3. Manual JSON extraction for LastMessageReceived
                        if let json = try? JSONSerialization.jsonObject(with: data) {
                            if let arr = json as? [[String: Any]], let first = arr.first {
                                if let lmr = first["LastMessageReceived"] as? String,
                                   let lmrData = lmr.data(using: .utf8),
                                   let lmrJson = try? JSONSerialization.jsonObject(with: lmrData) as? [String: Any],
                                   let valArr = lmrJson["Values"] as? [String] {
                                    return CloudStoveData(deviceKey: deviceKey, isOnline: first["IsOnline"] as? Bool, values: nil, Values: valArr, data: nil)
                                }
                                if let valArr = first["Values"] as? [String] {
                                    return CloudStoveData(deviceKey: deviceKey, isOnline: first["IsOnline"] as? Bool, values: nil, Values: valArr, data: nil)
                                }
                            } else if let dict = json as? [String: Any] {
                                if let valArr = dict["Values"] as? [String] {
                                    return CloudStoveData(deviceKey: deviceKey, isOnline: dict["IsOnline"] as? Bool, values: nil, Values: valArr, data: nil)
                                }
                            }
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
    
    /// Sends a command to the stove via Cloud API (using official Dielle 2ways payload format { "id": "...", "comando": ["2WC", "1", "..."] })
    func sendCommand(deviceKey: String, token: String, command: StoveCommand) async throws {
        self.activeError = nil
        
        let url = URL(string: "\(baseURL)/command")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        let commandArray: [String] = ["2WC", "1", command.rawString]
        
        // Exact payload format from official Dielle app controllers.js
        let body: [String: Any] = [
            "id": deviceKey,
            "comando": commandArray
        ]
        
        print("CLOUD SENDING 2WC to ID \(deviceKey): \(commandArray)")
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
