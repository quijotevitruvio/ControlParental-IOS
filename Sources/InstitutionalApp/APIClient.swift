import Foundation
import UIKit
import CoreLocation
import Combine
import OSLog

/// Shared networking client for institutional supervision app
/// Handles Bearer token authentication, retry logic, and offline queuing
final class APIClient {
    
    // MARK: - Singleton
    
    static let shared = APIClient()
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.institutional.supervision", category: "APIClient")
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    // Configuration from ManagedAppConfiguration
    @Published private(set) var baseURL: URL?
    @Published private(set) var bearerToken: String?
    @Published private(set) var orgID: String?
    @Published private(set) var caseID: String?
    @Published private(set) var apnsTopic: String?
    
    // Network monitoring
    private let networkMonitor = NetworkMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Request retries
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0
    
    // MARK: - Initialization
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.httpMaximumConnectionsPerHost = 5
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        
        // Observe network status changes
        observeNetworkStatus()
        
        // Load initial configuration
        loadConfiguration()
    }
    
    // MARK: - Configuration
    
    func loadConfiguration() {
        let config = ConfigManager.shared.configuration
        
        if let serverBase = config["server_base"] as? String,
           let url = URL(string: serverBase) {
            self.baseURL = url
            logger.info("Base URL configured: \(url.absoluteString)")
        }
        
        if let token = config["bearer_token"] as? String {
            self.bearerToken = token
            logger.debug("Bearer token loaded from config")
        }
        
        self.orgID = config["org_id"] as? String
        self.caseID = config["case_id"] as? String
        self.apnsTopic = config["apns_topic"] as? String
        
        logger.debug("Configuration loaded - orgID: \(self.orgID ?? "nil"), caseID: \(self.caseID ?? "nil")")
    }
    
    func updateBearerToken(_ token: String) {
        self.bearerToken = token
        logger.debug("Bearer token updated")
    }
    
    // MARK: - Safe URL Construction
    
    func endpointURL(_ path: String) -> URL {
        let base = (baseURL?.absoluteString ?? ConfigManager.shared.serverBase).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "\(base)/\(cleanPath)") ?? URL(string: "https://elojodeja.trescerbero.com/\(cleanPath)")!
    }
    
    // MARK: - Network Monitoring
    
    private func observeNetworkStatus() {
        networkMonitor.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                if isConnected {
                    self?.logger.info("Network connected - flushing pending requests")
                    Task {
                        await EventLogger.shared.flush()
                    }
                } else {
                    self?.logger.info("Network disconnected - queuing requests offline")
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Enrollment
    
    @discardableResult
    func enrollDevice(token: String = "auto") async throws -> String {
        let url = endpointURL("api/enroll.php")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (hwId, deviceName, deviceModel) = await MainActor.run {
            let hw = UIDevice.current.identifierForVendor?.uuidString.lowercased() ?? UUID().uuidString.lowercased()
            let name = UIDevice.current.name.isEmpty ? "iPhone" : UIDevice.current.name
            let model = UIDevice.currentModelCommercial
            return (hw, name, model)
        }
        
        let payload: [String: Any] = [
            "hw_id": hwId,
            "name": deviceName,
            "model": deviceModel,
            "platform": "ios",
            "enroll_token": token
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
            throw APIError.invalidResponse
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let devToken = json["device_token"] as? String, !devToken.isEmpty {
            self.bearerToken = devToken
            ConfigManager.shared.saveDeviceToken(devToken)
            logger.info("Device successfully enrolled with token: \(devToken)")
            return devToken
        } else {
            throw APIError.invalidResponse
        }
    }
    
    // MARK: - Public API Methods
    
    /// Register device token with backend
    func registerDeviceToken(_ token: String) async throws {
        let endpoint = Endpoint.registerDeviceToken
        let payload = DeviceTokenPayload(token: token, orgId: orgID, caseId: caseID)
        try await request(endpoint, method: .post, body: payload, responseType: EmptyResponse.self)
    }
    
    func updateDeviceToken(_ token: String) async throws {
        try await registerDeviceToken(token)
    }
    
    func sendInstitutionEvents(_ events: [[String: Any]]) async throws -> Bool {
        let endpoint = Endpoint.institutionEvents
        let payload: [String: Any] = ["events": events, "org_id": orgID, "case_id": caseID]
        let data = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request(endpoint, method: .post, body: data, responseType: EmptyResponse.self)
        return true
    }
    
    func uploadMedia(data: Data, type: String, meta: [String: Any]) async throws -> Bool {
        let endpoint = Endpoint.upload
        let lat = meta["latitude"] as? Double
        let lon = meta["longitude"] as? Double
        let acc = meta["accuracy"] as? Double
        let loc = (lat != nil && lon != nil) ? CLLocationCoordinate2D(latitude: lat!, longitude: lon!) : nil
        let evidence = SOSEvidence(
            mediaData: data,
            filename: "sos_capture.jpg",
            mimeType: "image/jpeg",
            timestamp: Date(),
            location: loc,
            horizontalAccuracy: acc
        )
        _ = try await uploadMultipart(endpoint, evidence: evidence)
        return true
    }
    
    func testConnection() async throws -> Bool {
        let endpoint = Endpoint.version
        _ = try await request(endpoint, method: .get, responseType: EmptyResponse.self)
        return true
    }
    
    /// Envía telemetría completa a /api/telemetry.php (batería, wifi, gps, etc.)
    @discardableResult
    func sendTelemetry(_ payload: [String: Any]) async throws -> [String: Any] {
        let url = endpointURL("api/telemetry.php")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Asegurar que exista token o re-enrolar
        var token = bearerToken
        if token == nil || token?.isEmpty == true {
            token = ConfigManager.shared.deviceToken
        }
        if token == nil || token?.isEmpty == true {
            token = try? await enrollDevice()
        }
        
        guard let validToken = token, !validToken.isEmpty else {
            throw APIError.unauthorized
        }
        
        request.setValue("Bearer \(validToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            logger.info("Telemetría aceptada por servidor: \(json["ok"] as? Bool ?? false)")
            return json
        }
        return [:]
    }
    
    /// Send institutional events to backend
    func sendEvents(_ events: [InstitutionEvent]) async throws {
        let endpoint = Endpoint.institutionEvents
        let payload = EventsPayload(events: events, orgId: orgID, caseId: caseID)
        try await request(endpoint, method: .post, body: payload, responseType: EmptyResponse.self)
    }
    
    /// Upload SOS evidence (image/video) with metadata
    func uploadSOS(_ evidence: SOSEvidence) async throws -> UploadResponse {
        let endpoint = Endpoint.upload
        return try await uploadMultipart(endpoint, evidence: evidence)
    }
    
    /// Fetch policy configuration from backend
    func fetchPolicy() async throws -> PolicyConfiguration {
        let endpoint = Endpoint.policy
        return try await request(endpoint, method: .get, responseType: PolicyConfiguration.self)
    }
    
    /// Fetch geofence configuration
    func fetchGeofences() async throws -> [GeofenceConfiguration] {
        let endpoint = Endpoint.geofences
        let response: GeofencesResponse = try await request(endpoint, method: .get, responseType: GeofencesResponse.self)
        return response.geofences
    }
    
    /// Send device boot event
    func sendDeviceBootEvent() async throws {
        let event = InstitutionEvent(
            type: .deviceBoot,
            timestamp: Date(),
            payload: DeviceBootPayload(
                osVersion: UIDevice.current.systemVersion,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                deviceModel: UIDevice.current.model
            )
        )
        try await sendEvents([event])
    }
    
    /// Send service alive heartbeat
    func sendServiceAliveEvent() async throws {
        let event = InstitutionEvent(
            type: .serviceAlive,
            timestamp: Date(),
            payload: ServiceAlivePayload(
                batteryLevel: UIDevice.current.batteryLevel,
                batteryState: UIDevice.current.batteryState.rawValue,
                networkType: networkMonitor.connectionType.rawValue
            )
        )
        try await sendEvents([event])
    }
    
    // MARK: - Core Request Methods
    
    private func request<R: Decodable>(
        _ endpoint: Endpoint,
        method: HTTPMethod,
        responseType: R.Type
    ) async throws -> R {
        return try await request(endpoint, method: method, body: nil as String?, responseType: responseType)
    }
    
    private func request<T: Encodable, R: Decodable>(
        _ endpoint: Endpoint,
        method: HTTPMethod,
        body: T? = nil,
        responseType: R.Type
    ) async throws -> R {
        guard let baseURL = baseURL else {
            throw APIError.configurationMissing("Base URL not configured")
        }
        
        let url = endpointURL(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Ensure authentication token exists, or enroll automatically!
        if bearerToken == nil || bearerToken?.isEmpty == true {
            _ = try? await enrollDevice()
        }
        
        // Add authentication
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Add org/case headers
        if let orgID = orgID {
            request.setValue(orgID, forHTTPHeaderField: "X-Org-ID")
        }
        if let caseID = caseID {
            request.setValue(caseID, forHTTPHeaderField: "X-Case-ID")
        }
        
        // Add device identifiers
        request.setValue(UIDevice.current.identifierForVendor?.uuidString ?? "unknown", forHTTPHeaderField: "X-Device-ID")
        request.setValue("iOS \(UIDevice.current.systemVersion)", forHTTPHeaderField: "X-Platform")
        
        // Encode body
        if let body = body {
            request.httpBody = try encoder.encode(body)
        }
        
        logger.debug("Request: \(method.rawValue) \(url.absoluteString)")
        
        return try await performRequestWithRetry(request, responseType: responseType)
    }
    
    private func performRequestWithRetry<R: Decodable>(
        _ request: URLRequest,
        responseType: R.Type,
        attempt: Int = 0
    ) async throws -> R {
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            logger.debug("Response: \(httpResponse.statusCode) for \(request.url?.absoluteString ?? "unknown")")
            
            // Handle status codes
            switch httpResponse.statusCode {
            case 200...299:
                if data.isEmpty, responseType == EmptyResponse.self {
                    return EmptyResponse() as! R
                }
                return try decoder.decode(responseType, from: data)
                
            case 401:
                if attempt == 0 {
                    logger.info("401 received, attempting auto-enrollment renewal...")
                    if let newToken = try? await enrollDevice() {
                        var newRequest = request
                        newRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        return try await performRequestWithRetry(newRequest, responseType: responseType, attempt: attempt + 1)
                    }
                }
                throw APIError.unauthorized
                
            case 403:
                throw APIError.forbidden
                
            case 429:
                // Rate limited - retry with backoff
                if attempt < maxRetries {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequestWithRetry(request, responseType: responseType, attempt: attempt + 1)
                }
                throw APIError.rateLimited
                
            case 500...599:
                // Server error - retry
                if attempt < maxRetries {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequestWithRetry(request, responseType: responseType, attempt: attempt + 1)
                }
                throw APIError.serverError(httpResponse.statusCode)
                
            default:
                throw APIError.httpError(httpResponse.statusCode, data)
            }
            
        } catch let error as APIError {
            throw error
        } catch {
            // Network error - retry if appropriate
            if attempt < maxRetries && isRetriableError(error) {
                let delay = baseRetryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performRequestWithRetry(request, responseType: responseType, attempt: attempt + 1)
            }
            throw APIError.networkError(error)
        }
    }
    
    private func uploadMultipart(_ endpoint: Endpoint, evidence: SOSEvidence) async throws -> UploadResponse {
        guard let baseURL = baseURL else {
            throw APIError.configurationMissing("Base URL not configured")
        }
        
        let url = endpointURL(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        
        // Ensure authentication token exists, or enroll automatically!
        if bearerToken == nil || bearerToken?.isEmpty == true {
            _ = try? await enrollDevice()
        }
        
        // Add authentication
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let orgID = orgID {
            request.setValue(orgID, forHTTPHeaderField: "X-Org-ID")
        }
        if let caseID = caseID {
            request.setValue(caseID, forHTTPHeaderField: "X-Case-ID")
        }
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add metadata fields
        let metadata: [String: String] = [
            "org_id": orgID ?? "",
            "case_id": caseID ?? "",
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "timestamp": ISO8601DateFormatter().string(from: evidence.timestamp),
            "latitude": String(evidence.location?.latitude ?? 0),
            "longitude": String(evidence.location?.longitude ?? 0),
            "accuracy": String(evidence.horizontalAccuracy ?? 0),
            "event_type": "sos_button"
        ]
        
        for (key, value) in metadata {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        
        // Add media file
        if let mediaData = evidence.mediaData {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"media\"; filename=\"\(evidence.filename)\"\r\n")
            body.append("Content-Type: \(evidence.mimeType)\r\n\r\n")
            body.append(mediaData)
            body.append("\r\n")
        }
        
        body.append("--\(boundary)--\r\n")
        request.httpBody = body
        
        logger.debug("Uploading SOS evidence: \(evidence.filename), size: \(evidence.mediaData?.count ?? 0) bytes")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode, data)
        }
        
        return try decoder.decode(UploadResponse.self, from: data)
    }
    
    // MARK: - Helpers
    
    private func isRetriableError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // Retry on network timeouts, connection lost, etc.
        return nsError.domain == NSURLErrorDomain && [
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorDataNotAllowed
        ].contains(nsError.code)
    }
}

// MARK: - Supporting Types

private enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

private enum Endpoint {
    case registerDeviceToken
    case institutionEvents
    case upload
    case policy
    case geofences
    case version
    
    var path: String {
        switch self {
        case .registerDeviceToken: return "/api/register.php"
        case .institutionEvents: return "/api/institution_events.php"
        case .upload: return "/api/upload.php"
        case .policy: return "/api/policy.php"
        case .geofences: return "/api/geofences.php"
        case .version: return "/api/telemetry.php"
        }
    }
}

// MARK: - Request/Response Models

struct DeviceTokenPayload: Encodable {
    let token: String
    let orgId: String?
    let caseId: String?
}

struct EventsPayload: Encodable {
    let events: [InstitutionEvent]
    let orgId: String?
    let caseId: String?
}

struct InstitutionEvent: Encodable {
    let type: EventType
    let timestamp: Date
    let payload: Encodable
    
    enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case payload
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        try payload.encode(to: container.superEncoder(forKey: .payload))
    }
}

enum EventType: String, Encodable {
    case deviceBoot = "device_boot"
    case serviceAlive = "service_alive"
    case locationUpdate = "location_update"
    case appUsageSummary = "app_usage_summary"
    case networkInfo = "network_info"
    case batteryStatus = "battery_status"
    case geofenceEnter = "geofence_enter"
    case geofenceExit = "geofence_exit"
    case locationPermissionRevoked = "location_permission_revoked"
    case sosButton = "sos_button"
    case policyUpdate = "policy_update"
}

struct DeviceBootPayload: Encodable {
    let osVersion: String
    let appVersion: String
    let deviceModel: String
}

struct ServiceAlivePayload: Encodable {
    let batteryLevel: Float
    let batteryState: Int
    let networkType: String
}

struct SOSEvidence {
    let mediaData: Data?
    let filename: String
    let mimeType: String
    let timestamp: Date
    let location: CLLocationCoordinate2D?
    let horizontalAccuracy: Double?
}

import CoreLocation

struct UploadResponse: Decodable {
    let success: Bool
    let fileId: String?
    let url: String?
    let message: String?
}

struct PolicyConfiguration: Decodable {
    let riskThresholds: RiskThresholds
    let geofences: [GeofenceConfiguration]
    let reportingInterval: TimeInterval
    let allowedApps: [String]?
    let blockedApps: [String]?
}

struct RiskThresholds: Decodable {
    let batteryCritical: Float
    let batteryLow: Float
    let locationAccuracyThreshold: Double
    let maxOfflineDuration: TimeInterval
}

struct GeofenceConfiguration: Decodable {
    let id: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let name: String
    let type: GeofenceType
    let notifyOnEntry: Bool
    let notifyOnExit: Bool
}

enum GeofenceType: String, Decodable {
    case school = "school"
    case home = "home"
    case restricted = "restricted"
    case safe = "safe"
}

struct GeofencesResponse: Decodable {
    let geofences: [GeofenceConfiguration]
}

struct EmptyResponse: Decodable {
    let success: Bool = true
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case configurationMissing(String)
    case invalidResponse
    case unauthorized
    case forbidden
    case rateLimited
    case serverError(Int)
    case httpError(Int, Data)
    case networkError(Error)
    case decodingError(Error)
    case encodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .configurationMissing(let detail):
            return "Configuration missing: \(detail)"
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "Authentication failed - token may be expired"
        case .forbidden:
            return "Access forbidden"
        case .rateLimited:
            return "Rate limited by server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .httpError(let code, let data):
            if let message = String(data: data, encoding: .utf8) {
                return "HTTP \(code): \(message)"
            }
            return "HTTP error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Encoding error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Data Extensions

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

// MARK: - Commercial Model Detection

extension UIDevice {
    static var currentModelCommercial: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        switch identifier {
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        case "iPhone18,1": return "iPhone 17 Pro"
        case "iPhone18,2": return "iPhone 17 Pro Max"
        case "iPhone18,3": return "iPhone 18 Pro Max"
        case "iPhone18,4": return "iPhone 18 Pro"
        default:
            if identifier.contains("iPhone") {
                return identifier
            }
            let name = UIDevice.current.name
            if name.contains("iPhone") { return name }
            return "iPhone 18 Pro Max"
        }
    }
}