import Foundation
import Network
import Combine
import OSLog

/// Monitors network connectivity and connection type
final class NetworkMonitor {
    
    static let shared = NetworkMonitor()
    
    private let logger = Logger(subsystem: "com.institutional.supervision", category: "NetworkMonitor")
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.institutional.supervision.networkmonitor")
    
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var connectionType: ConnectionType = .unknown
    @Published private(set) var isExpensive: Bool = false
    @Published private(set) var isConstrained: Bool = false
    
    private init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updatePath(path)
            }
        }
        monitor.start(queue: queue)
        logger.info("Network monitoring started")
    }
    
    func stopMonitoring() {
        monitor.cancel()
        logger.info("Network monitoring stopped")
    }
    
    private func updatePath(_ path: NWPath) {
        let wasConnected = isConnected
        isConnected = path.status == .satisfied
        
        // Determine connection type
        let newType: ConnectionType
        if path.usesInterfaceType(.wifi) {
            newType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            newType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            newType = .ethernet
        } else {
            newType = .unknown
        }
        
        connectionType = newType
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        
        if isConnected != wasConnected {
            logger.info("Network status changed: connected=\(self.isConnected), type=\(self.connectionType.rawValue)")
            NotificationCenter.default.post(name: .networkStatusChanged, object: nil)
        }
    }
    
    enum ConnectionType: String, CaseIterable {
        case wifi = "wifi"
        case cellular = "cellular"
        case ethernet = "ethernet"
        case unknown = "unknown"
        
        var displayName: String {
            switch self {
            case .wifi: return "Wi-Fi"
            case .cellular: return "Celular"
            case .ethernet: return "Ethernet"
            case .unknown: return "Desconocido"
            }
        }
    }
    
    // MARK: - API pública usada por TelemetryManager
    
    var isVPNActive: Bool {
        let path = monitor.currentPath
        return path.usesInterfaceType(.other) && path.isExpensive
    }
    
    func currentNetworkInfo() async -> [String: Any] {
        var info: [String: Any] = [:]
        let path = monitor.currentPath
        info["net_type"] = connectionType.rawValue
        info["conn"] = connectionType.rawValue
        info["is_expensive"] = path.isExpensive
        info["is_constrained"] = path.isConstrained
        return info
    }
    
    var connectionTypeDescription: String {
        connectionType.displayName
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let networkStatusChanged = Notification.Name("com.institutional.supervision.networkStatusChanged")
}