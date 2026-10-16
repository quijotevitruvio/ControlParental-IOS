//
//  InstitutionalAppTests.swift
//  InstitutionalAppTests
//
//  Pruebas unitarias para la arquitectura nativa, persistencia en Keychain,
//  cola offline de eventos, CallKit, Geocercas y escaneo QR de enrolamiento.
//

import XCTest
@testable import InstitutionalApp

final class InstitutionalAppTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: - 1. Keychain & ConfigManager Tests
    
    func testConfigManagerPersistence() {
        let config = ConfigManager.shared
        let testToken = "test_device_token_\(UUID().uuidString)"
        
        config.saveDeviceToken(testToken)
        XCTAssertEqual(config.deviceToken, testToken)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "device_token"), testToken)
        
        let testPinHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        config.savePinHash(testPinHash)
        XCTAssertEqual(config.pinHash, testPinHash)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "parental_pin_hash_v1"), testPinHash)
        
        let testApns = "apns_hex_token_1234567890abcdef"
        config.saveApnsToken(testApns)
        XCTAssertEqual(config.apnsToken, testApns)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "apns_token"), testApns)
        
        XCTAssertFalse(config.hardwareID.isEmpty)
    }
    
    // MARK: - 2. EventLogger & Offline Queue Tests
    
    func testEventLoggerQueueAndFlushing() {
        let logger = EventLogger.shared
        logger.clearAll()
        
        let id1 = UUID()
        let id2 = UUID()
        
        let event1 = QueuedEvent(id: id1, type: "location", timestamp: Date(), meta: ["lat": 4.6097, "lng": -74.0817])
        let event2 = QueuedEvent(id: id2, type: "geofence_enter", timestamp: Date(), meta: ["geofence": "colegio"])
        
        logger.enqueue(event1)
        logger.enqueue(event2)
        
        let pending = logger.pendingEvents(limit: 10)
        XCTAssertEqual(pending.count, 2)
        
        // Marcar uno como enviado
        logger.markAsSent(ids: [id1])
        
        let remaining = logger.pendingEvents(limit: 10)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, id2)
        
        logger.clearAll()
        XCTAssertEqual(logger.pendingCount, 0)
    }
    
    // MARK: - 3. CallBlockerManager & Policy Sync Tests
    
    func testCallBlockerPolicySync() {
        let blocker = CallBlockerManager.shared
        
        let testNumber1 = "+57 300 123 4567"
        let testNumber2 = "+1 800 555 0199"
        
        blocker.syncFromPolicy([testNumber1, testNumber2])
        
        XCTAssertTrue(blocker.isNumberBlocked("+573001234567"))
        XCTAssertTrue(blocker.isNumberBlocked("+18005550199"))
        
        // Verificar persistencia en UserDefaults plano
        let flatNumbers = UserDefaults.standard.stringArray(forKey: "blocked_phone_numbers") ?? []
        XCTAssertTrue(flatNumbers.contains("+573001234567"))
        XCTAssertTrue(flatNumbers.contains("+18005550199"))
        
        blocker.removeNumber(byString: testNumber1)
        XCTAssertFalse(blocker.isNumberBlocked("+573001234567"))
    }
    
    // MARK: - 4. GeofenceZone Parsing Tests
    
    func testGeofenceZoneParsing() {
        let rawZone1: [String: Any] = [
            "id": 42,
            "name": "Zona Norte",
            "lat": 4.7110,
            "lng": -74.0721,
            "radius_m": 250.0
        ]
        
        let zone1 = GeofenceZone(dict: rawZone1)
        XCTAssertNotNil(zone1)
        XCTAssertEqual(zone1?.id, "42")
        XCTAssertEqual(zone1?.name, "Zona Norte")
        XCTAssertEqual(zone1?.lat, 4.7110)
        XCTAssertEqual(zone1?.lng, -74.0721)
        XCTAssertEqual(zone1?.radiusMeters, 250.0)
        
        let rawZone2: [String: Any] = [
            "id": "zone_school",
            "latitude": "4.6500",
            "longitude": "-74.1000",
            "radius": 150.0
        ]
        
        let zone2 = GeofenceZone(dict: rawZone2)
        XCTAssertNotNil(zone2)
        XCTAssertEqual(zone2?.id, "zone_school")
        XCTAssertEqual(zone2?.radiusMeters, 150.0)
    }
    
    // MARK: - 5. QR Code Enrollment Parser Tests
    
    func testQRScannerParsingJSON() {
        let jsonQR = "{\"server\": \"https://elojodeja.trescerbero.com\", \"token\": \"secure_enroll_token_999\"}"
        let parsed = QRScannerView.parseEnrollmentCode(jsonQR)
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.server, "https://elojodeja.trescerbero.com")
        XCTAssertEqual(parsed?.token, "secure_enroll_token_999")
    }
    
    func testQRScannerParsingURL() {
        let urlQR = "https://elojodeja.trescerbero.com/panel/?token=url_token_abc_123"
        let parsed = QRScannerView.parseEnrollmentCode(urlQR)
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.server, "https://elojodeja.trescerbero.com")
        XCTAssertEqual(parsed?.token, "url_token_abc_123")
    }
    
    func testQRScannerParsingRawToken() {
        let rawToken = "d41d8cd98f00b204e9800998ecf8427e"
        let parsed = QRScannerView.parseEnrollmentCode(rawToken)
        
        XCTAssertNotNil(parsed)
        XCTAssertNil(parsed?.server)
        XCTAssertEqual(parsed?.token, rawToken)
    }
    
    // MARK: - 6. API Response Decoding Tests
    
    func testUploadResponseDecoding() throws {
        let jsonOk = "{\"ok\": true, \"path\": \"1/photo_123.jpg\"}".data(using: .utf8)!
        let response1 = try JSONDecoder().decode(UploadResponse.self, from: jsonOk)
        XCTAssertTrue(response1.isSuccess)
        XCTAssertEqual(response1.path, "1/photo_123.jpg")
        
        let jsonSuccess = "{\"success\": true, \"file_url\": \"https://test.com/img.jpg\"}".data(using: .utf8)!
        let response2 = try JSONDecoder().decode(UploadResponse.self, from: jsonSuccess)
        XCTAssertTrue(response2.isSuccess)
    }
    
    func testServerResponseDecoding() throws {
        let json1 = "{\"ok\": true, \"summary\": {\"processed\": 1}}".data(using: .utf8)!
        let res1 = try JSONDecoder().decode(ServerResponse.self, from: json1)
        XCTAssertTrue(res1.isSuccess)
        
        let json2 = "{\"status\": \"ok\"}".data(using: .utf8)!
        let res2 = try JSONDecoder().decode(ServerResponse.self, from: json2)
        XCTAssertTrue(res2.isSuccess)
        
        let empty = "{}".data(using: .utf8)!
        let emptyRes = try JSONDecoder().decode(EmptyResponse.self, from: empty)
        XCTAssertTrue(emptyRes.success)
    }
}
