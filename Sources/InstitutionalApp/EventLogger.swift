import Foundation
import Combine
import OSLog

/// Tipo de evento institucional (debe coincidir con lib/risk.php en el backend)
enum InstitutionEventType: String, Codable {
    case deviceBoot = "device_boot"
    case serviceAlive = "service_alive"
    case locationUpdate = "location_update"
    case geofenceEnter = "geofence_enter"
    case geofenceExit = "geofence_exit"
    case vpnDetected = "vpn_detected"
    case airplaneModeOn = "airplane_mode_on"
    case appUsageSummary = "app_usage_summary"
    case networkInfo = "network_info"
    case batteryStatus = "battery_status"
    case riskSelfharm = "risk_selfharm"
    case riskGrooming = "risk_grooming"
    case riskViolence = "risk_violence"
    case sosButton = "sos_button"
    case policyViolation = "policy_violation"
    case locationPermissionRevoked = "location_permission_revoked"
    case custom = "custom"
}

/// Offline event queue with persistence - mirrors Android's InstitutionEventLogger
final class EventLogger {
    
    static let shared = EventLogger()
    
    private let logger = Logger(subsystem: "com.institutional.supervision", category: "EventLogger")
    
    // Storage keys
    private let queueKey = "com.institutional.supervision.eventQueue"
    private let maxQueueSize = 1000
    private let flushInterval: TimeInterval = 300 // 5 minutes
    
    // In-memory queue
    private var eventQueue: [QueuedEvent] = []
    private let queueLock = NSLock()
    
    // Flush timer
    private var flushTimer: Timer?
    
    // Dependencies
    private let apiClient = APIClient.shared
    private let networkMonitor = NetworkMonitor.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadQueue()
        startFlushTimer()
        observeNetworkChanges()
        observeSilentPushTrigger()
    }
    
    deinit {
        flushTimer?.invalidate()
    }
    
    // MARK: - Public API
    
    /// Add event to queue for later sending
    func enqueue(_ event: InstitutionEvent) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        // Check queue size limit
        if eventQueue.count >= maxQueueSize {
            // Remove oldest non-critical events
            eventQueue.removeFirst()
            logger.warning("Event queue full, removed oldest event")
        }
        
        let queuedEvent = QueuedEvent(
            id: UUID(),
            event: event,
            timestamp: Date(),
            retryCount: 0
        )
        eventQueue.append(queuedEvent)
        persistQueue()
        
        logger.debug("Enqueued event: \(event.type.rawValue), queue size: \(self.eventQueue.count)")
    }
    
    /// Add multiple events at once
    func enqueue(_ events: [InstitutionEvent]) {
        events.forEach { enqueue($0) }
    }
    
    /// Flush queue to server
    func flush() async {
        guard networkMonitor.isConnected else {
            logger.debug("Network not available, skipping flush")
            return
        }
        
        let eventsToSend: [QueuedEvent]
        queueLock.lock()
        eventsToSend = eventQueue
        queueLock.unlock()
        
        guard !eventsToSend.isEmpty else { return }
        
        logger.info("Flushing \(eventsToSend.count) events to server")
        
        do {
            let events = eventsToSend.map { $0.event }
            try await apiClient.sendEvents(events)
            
            // Clear queue on success
            queueLock.lock()
            eventQueue.removeAll()
            queueLock.unlock()
            persistQueue()
            
            logger.info("Successfully flushed \(eventsToSend.count) events")
            
        } catch {
            logger.error("Failed to flush events: \(error.localizedDescription)")
            
            // Increment retry counts
            queueLock.lock()
            for i in eventQueue.indices {
                eventQueue[i].retryCount += 1
            }
            // Remove events that have failed too many times
            eventQueue.removeAll { $0.retryCount > 5 }
            queueLock.unlock()
            persistQueue()
        }
    }
    
    /// Get current queue count (for UI)
    var queueCount: Int {
        queueLock.lock()
        defer { queueLock.unlock() }
        return eventQueue.count
    }
    
    /// Get events for UI display
    var queuedEvents: [QueuedEvent] {
        queueLock.lock()
        defer { queueLock.unlock() }
        return eventQueue
    }
    
    var pendingCount: Int { queueCount }
    
    func pendingEvents() async -> [QueuedEvent] {
        queueLock.lock(); defer { queueLock.unlock() }
        return eventQueue
    }
    
    func markAsSent(_ events: [QueuedEvent]) async {
        queueLock.lock()
        let ids = Set(events.map { $0.id })
        eventQueue.removeAll { ids.contains($0.id) }
        queueLock.unlock()
        persistQueue()
    }
    
    func clearAll() {
        queueLock.lock()
        eventQueue.removeAll()
        queueLock.unlock()
        persistQueue()
    }
    
    func log(type: String, meta: [String: Any]?) async {
        let event = InstitutionEvent(
            type: EventType(rawValue: type) ?? .custom,
            timestamp: Date(),
            payload: meta ?? [:]
        )
        enqueue(event)
    }
    
    var pendingCount: Int { queueCount }
    
    func pendingEvents() async -> [QueuedEvent] {
        queueLock.lock(); defer { queueLock.unlock() }
        return eventQueue
    }
    
    func markAsSent(_ events: [QueuedEvent]) async {
        queueLock.lock()
        let ids = Set(events.map { $0.id })
        eventQueue.removeAll { ids.contains($0.id) }
        queueLock.unlock()
        persistQueue()
    }
    
    func clearAll() {
        queueLock.lock()
        eventQueue.removeAll()
        queueLock.unlock()
        persistQueue()
    }
    
    func log(type: String, meta: [String: Any]?) async {
        let event = InstitutionEvent(
            type: EventType(rawValue: type) ?? .custom,
            timestamp: Date(),
            payload: meta ?? [:]
        )
        enqueue(event)
    }
    
    var pendingCount: Int { queueCount }
    
    func pendingEvents() async -> [QueuedEvent] {
        queueLock.lock(); defer { queueLock.unlock() }
        return eventQueue
    }
    
    func markAsSent(_ events: [QueuedEvent]) async {
        queueLock.lock()
        let ids = Set(events.map { $0.id })
        eventQueue.removeAll { ids.contains($0.id) }
        queueLock.unlock()
        persistQueue()
    }
    
    func clearAll() {
        queueLock.lock()
        eventQueue.removeAll()
        queueLock.unlock()
        persistQueue()
    }
    
    func log(type: String, meta: [String: Any]?) async {
        let event = InstitutionEvent(
            type: EventType(rawValue: type) ?? .custom,
            timestamp: Date(),
            payload: meta ?? [:]
        )
        enqueue(event)
    }
    
    var pendingCount: Int { queueCount }
    
    func pendingEvents() async -> [QueuedEvent] {
        queueLock.lock(); defer { queueLock.unlock() }
        return eventQueue
    }
    
    func markAsSent(_ events: [QueuedEvent]) async {
        queueLock.lock()
        let ids = Set(events.map { $0.id })
        eventQueue.removeAll { ids.contains($0.id) }
        queueLock.unlock()
        persistQueue()
    }
    
    func clearAll() {
        queueLock.lock()
        eventQueue.removeAll()
        queueLock.unlock()
        persistQueue()
    }
    
    func log(type: String, meta: [String: Any]?) async {
        let event = InstitutionEvent(
            id: UUID(),
            type: InstitutionEventType(rawValue: type) ?? .custom,
            timestamp: Date(),
            metadata: meta ?? [:]
        )
        enqueue(event)
    }
    
    var pendingCount: Int { queueCount }
    
    func pendingEvents() async -> [QueuedEvent] {
        queueLock.lock(); defer { queueLock.unlock() }
        return eventQueue
    }
    
    func markAsSent(_ events: [QueuedEvent]) async {
        queueLock.lock()
        let ids = Set(events.map { $0.id })
        eventQueue.removeAll { ids.contains($0.id) }
        queueLock.unlock()
        persistQueue()
    }
    
    func clearAll() {
        queueLock.lock()
        eventQueue.removeAll()
        queueLock.unlock()
        persistQueue()
    }
    
    func log(type: String, meta: [String: Any]?) async {
        let event = InstitutionEvent(
            id: UUID(),
            type: InstitutionEventType(rawValue: type) ?? .custom,
            timestamp: Date(),
            metadata: meta ?? [:]
        )
        enqueue(event)
    }
    
    var pendingCount: Int { queueCount }
    
    func pendingEvents() async -> [QueuedEvent] {
        queueLock.lock(); defer { queueLock.unlock() }
        return eventQueue
    }
    
    func markAsSent(_ events: [QueuedEvent]) async {
        queueLock.lock()
        let ids = Set(events.map { $0.id })
        eventQueue.removeAll { ids.contains($0.id) }
        queueLock.unlock()
        persistQueue()
    }
    
    func clearAll() {
        queueLock.lock()
        eventQueue.removeAll()
        queueLock.unlock()
        persistQueue()
    }
    
    func log(type: String, meta: [String: Any]?) async {
        let event = InstitutionEvent(
            id: UUID(),
            type: InstitutionEventType(rawValue: type) ?? .custom,
            timestamp: Date(),
            metadata: meta ?? [:]
        )
        enqueue(event)
    }
    
    // MARK: - Private Methods
    
    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.flush()
            }
        }
        RunLoop.main.add(flushTimer!, forMode: .common)
    }
    
    private func observeNetworkChanges() {
        networkMonitor.$isConnected
            .filter { $0 }
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.flush()
                }
            }
            .store(in: &cancellables)
    }
    
    private func observeSilentPushTrigger() {
        NotificationCenter.default.publisher(for: .silentPushFlushQueue)
            .sink { [weak self] _ in
                Task {
                    await self?.flush()
                }
            }
            .store(in: &cancellables)
    }
    
    private func persistQueue() {
        do {
            let data = try JSONEncoder().encode(eventQueue)
            UserDefaults.standard.set(data, forKey: queueKey)
        } catch {
            logger.error("Failed to persist event queue: \(error.localizedDescription)")
        }
    }
    
    private func loadQueue() {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return }
        
        do {
            eventQueue = try JSONDecoder().decode([QueuedEvent].self, from: data)
            logger.info("Loaded \(self.eventQueue.count) events from persistent storage")
        } catch {
            logger.error("Failed to load event queue: \(error.localizedDescription)")
            eventQueue = []
        }
    }
}

// MARK: - Queued Event Model

struct QueuedEvent: Codable {
    let id: UUID
    let event: InstitutionEvent
    let timestamp: Date
    var retryCount: Int
}

// MARK: - Notification Names

extension Notification.Name {
    static let silentPushFlushQueue = Notification.Name("com.institutional.supervision.silentPushFlushQueue")
}