import XCTest

final class VibeProtocolTests: XCTestCase {
    func testAgentPressMatchesOriginalVendorReportFraming() throws {
        let event = VibeEvent.agent(index: 0, phase: .pressed)
        let bytes = [UInt8](event.vendorReport)

        XCTAssertEqual(bytes.count, 63)
        XCTAssertEqual(bytes[0], 2)
        XCTAssertEqual(Int(bytes[1]), event.jsonLine.utf8.count)
        XCTAssertEqual(
            String(decoding: bytes[2..<(2 + Int(bytes[1]))], as: UTF8.self),
            #"{"m":"v.oai.hid","p":{"k":"AG00","act":1}}"# + "\r\n"
        )
    }

    func testWatchMessageRoundTrip() throws {
        let source = VibeEvent.control(.ok, phase: .released)
        let decoded = try XCTUnwrap(VibeEvent(watchMessage: source.watchMessage))

        XCTAssertEqual(decoded.id, source.id)
        XCTAssertEqual(decoded.key, source.key)
        XCTAssertEqual(decoded.phase, source.phase)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, source.createdAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(decoded.vendorReport, source.vendorReport)
    }

    func testActionKeysMatchVibeWatchFirmware() {
        XCTAssertEqual(VibeControl.fast.rawValue, "ACT06")
        XCTAssertEqual(VibeControl.ok.rawValue, "ACT07")
        XCTAssertEqual(VibeControl.ng.rawValue, "ACT08")
        XCTAssertEqual(VibeControl.plan.rawValue, "ACT09")
        XCTAssertEqual(VibeControl.microphonePrimary.rawValue, "ACT10")
        XCTAssertEqual(VibeControl.microphoneSecondary.rawValue, "ACT11")
        XCTAssertEqual(VibeControl.assistant.rawValue, "ACT12")
    }

    func testBridgeEnvelopeRoundTrip() throws {
        let event = VibeEvent.control(.fast, phase: .pressed)
        let source = BridgeRequest(pairingCode: "123456", event: event)
        let decoded = try JSONDecoder().decode(
            BridgeRequest.self,
            from: JSONEncoder().encode(source)
        )

        XCTAssertEqual(decoded.pairingCode, "123456")
        XCTAssertEqual(decoded.event, event)
    }
}
