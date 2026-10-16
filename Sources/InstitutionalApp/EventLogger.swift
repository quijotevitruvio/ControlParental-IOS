import Foundation
import Combine
import OSLog

/// Offline event queue with persistence - mirrors Android's InstitutionEventLogger
final class EventLogger: ObservableObject {
    
    static let shared = EventLogger()
    
    private let logger = Logger(subsystem: "com.institutional.supervision", category: "EventLogger")
    
    // Storage keys
    private let queueKey = "com.institutional.supervision.eventQueue"
    private let maxQueueSize = 1000
    private let flushInterval: TimeInterval = 300 // 5 minutes
    
    // In-memory queue
    private var eventQueue: [QueuedEvent] = []
    private let queueLock = NSLock()
    
    @Published var queueCount: Int = 0
    
    // Flush timer
    private var flushTimer: Timer?
    
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
    
    var pendingCount: Int {
        queueLock.lock()
        defer { queueLock.unlock() }
        return eventQueue.count
    }
    
    var queuedEvents: [QueuedEvent] {
        queueLock.lock()
        defer { queueLock.unlock() }
        return eventQueue
    }
    
    func enqueue(_ event: QueuedEvent) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        if eventQueue.count >= maxQueueSize {
            eventQueue.removeFirst()
            logger.warning("Event queue full, removed oldest event")
        }
        
        eventQueue.append(event)
        DispatchQueue.main.async {
            self.queueCount = self.eventQueue.count
        }
        persistQueue()
        logger.debug("Enqueued event: \(event.type), queue size: \(self.eventQueue.count)")
    }
    
    func log(type: String, meta: [String: Any]? = nil) {
        let queued = QueuedEvent(type: type, meta: meta)
        enqueue(queued)
    }
    
    func pendingEvents(limit: Int = 100) -> [QueuedEvent] {
        queueLock.lock()
        defer { queueLock.unlock() }
        return Array(eventQueue.prefix(limit))
    }
    
    func pendingEvents() async -> [QueuedEvent] {
        return pendingEvents(limit: 1000)
    }
    
    func markAsSent(ids: [UUID]) {
        queueLock.lock()
        let idSet = Set(ids)
        eventQueue.removeAll { idSet.contains($0.id) }
        let count = eventQueue.count
        queueLock.unlock()
        
        DispatchQueue.main.async {
            self.queueCount = count
        }
        persistQueue()
    }
    
    func markAsSent(ids: Set<UUID>) {
        markAsSent(ids: Array(ids))
    }
    
    func markAsSent(_ events: [QueuedEvent]) async {
        markAsSent(ids: events.map { $0.id })
    }
    
    func clearAll() {
        queueLock.lock()
        eventQueue.removeAll()
        queueLock.unlock()
        
        DispatchQueue.main.async {
            self.queueCount = 0
        }
        persistQueue()
    }
    
    func flush() async {
        await TelemetryManager.shared.flushEvents()
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
        NotificationCenter.default.publisher(for: .networkStatusChanged)
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
            queueCount = eventQueue.count
            logger.info("Loaded \(self.eventQueue.count) events from persistent storage")
        } catch {
            logger.error("Failed to load event queue: \(error.localizedDescription)")
            eventQueue = []
        }
    }
}

// MARK: - Queued Event Model

struct QueuedEvent: Codable, Identifiable {
    let id: UUID
    let type: String
    let timestamp: Date
    let metaJSON: String
    var retryCount: Int
    
    init(id: UUID = UUID(), type: String, timestamp: Date = Date(), meta: [String: Any]? = nil, retryCount: Int = 0) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        if let meta = meta,
           let data = try? JSONSerialization.data(withJSONObject: meta, options: []),
           let str = String(data: data, encoding: .utf8) {
            self.metaJSON = str
        } else {
            self.metaJSON = "{}"
        }
        self.retryCount = retryCount
    }
    
    var metaDict: [String: Any] {
        guard let data = metaJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
    
    var asDictionary: [String: Any] {
        return [
            "id": id.uuidString,
            "type": type,
            "occurred_at": ISO8601DateFormatter().string(from: timestamp),
            "meta": metaDict
        ]
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let silentPushFlushQueue = Notification.Name("com.institutional.supervision.silentPushFlushQueue")
}