import Foundation
import Combine

public struct StoveDevice: Codable, Identifiable, Equatable {
    public let id: String        // The DeviceKey GUID or DeviceId
    public let name: String
    public let serialNumber: String?
    public let values: [String]?
    
    enum CodingKeys: String, CodingKey {
        case deviceKey = "DeviceKey"
        case deviceId = "DeviceId"
        case id = "id"
        case name = "Name"
        case serialNumber = "SerialNumber"
        case values = "Values"
    }
    
    public init(id: String, name: String, serialNumber: String? = nil, values: [String]? = nil) {
        self.id = id
        self.name = name
        self.serialNumber = serialNumber
        self.values = values
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let foundId = (try? container.decode(String.self, forKey: .deviceId))
            ?? (try? container.decode(String.self, forKey: .deviceKey))
            ?? (try? container.decode(String.self, forKey: .id))
            ?? ""
        self.id = foundId
        self.name = (try? container.decode(String.self, forKey: .name)) ?? "Dielle Ofen"
        self.serialNumber = (try? container.decode(String.self, forKey: .serialNumber))
            ?? (foundId.count <= 10 && !foundId.isEmpty ? foundId : nil)
        self.values = try? container.decodeIfPresent([String].self, forKey: .values)
    }
}

@MainActor
class AuthService: ObservableObject {
    @Published var token: String?
    @Published var isAuthenticated = false
    @Published var activeError: StoveError?
    @Published var devices: [StoveDevice] = []
    
    private(set) public var baseURL = "https://wifi4heat.azurewebsites.net"
    
    func setBaseURL(_ url: String) {
        self.baseURL = url
    }
    
    func login(email: String, password: String) async throws {
        self.activeError = nil
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let tokenURL = URL(string: "\(baseURL)/Token")!
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let encodedEmail = cleanEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanEmail
        let encodedPassword = cleanPassword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanPassword
        let body = "grant_type=password&username=\(encodedEmail)&password=\(encodedPassword)"
        request.httpBody = body.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            if statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = json["access_token"] as? String {
                    self.token = token
                    self.isAuthenticated = true
                    self.activeError = nil
                    UserDefaults.standard.set(token, forKey: "cloud_token")
                    
                    // Safely attempt device fetch without breaking valid token login
                    try? await fetchDevices()
                    self.activeError = nil
                    return
                }
            } else if statusCode == 400 || statusCode == 401 {
                let err = StoveError.loginFailed(message: "E-Mail oder Passwort ist ungültig (HTTP \(statusCode)).")
                self.activeError = err
                throw err
            } else {
                let err = StoveError.cloudNetworkError(message: "Server antwortete mit Status \(statusCode).")
                self.activeError = err
                throw err
            }
        } catch let err as StoveError {
            throw err
        } catch {
            let err = StoveError.cloudNetworkError(message: error.localizedDescription)
            self.activeError = err
            throw err
        }
    }
    
    /// Fetches the user device list from 4Heat Cloud API
    func fetchDevices() async throws {
        guard isAuthenticated, let token = token else { return }
        
        let endpoints = ["/api/devices", "/api/Devices", "/api/devices/Summary"]
        
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
                    if let decoded = try? JSONDecoder().decode([StoveDevice].self, from: data), !decoded.isEmpty {
                        self.devices = decoded
                        print("DEBUG: \(decoded.count) Geräte von \(ep) geladen.")
                        return
                    }
                    
                    // Flexible fallback JSON parsing
                    if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !jsonArray.isEmpty {
                        let parsed = jsonArray.compactMap { item -> StoveDevice? in
                            let id = item["DeviceId"] as? String ?? item["DeviceKey"] as? String ?? item["id"] as? String ?? ""
                            guard !id.isEmpty else { return nil }
                            let name = item["Name"] as? String ?? item["nome"] as? String ?? "Dielle Ofen"
                            let sn = item["SerialNumber"] as? String ?? item["serial"] as? String ?? (id.count <= 10 ? id : nil)
                            return StoveDevice(id: id, name: name, serialNumber: sn)
                        }
                        if !parsed.isEmpty {
                            self.devices = parsed
                            print("DEBUG: \(parsed.count) Geräte via JSON geglättet.")
                            return
                        }
                    }
                }
            } catch {
                print("DEBUG: Fetch devices error on \(ep): \(error.localizedDescription)")
            }
        }
        
        self.devices = [StoveDevice(id: "25016460", name: "Dielle Ofen", serialNumber: "25016460")]
        self.activeError = nil
    }
    
    func logout() {
        self.token = nil
        self.isAuthenticated = false
        self.devices = []
        self.activeError = nil
        UserDefaults.standard.removeObject(forKey: "cloud_token")
    }
}
