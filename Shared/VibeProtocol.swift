import Foundation

enum VibeControl: String, Codable, CaseIterable, Identifiable, Sendable {
    case fast = "ACT06"
    case ok = "ACT07"
    case ng = "ACT08"
    case plan = "ACT09"
    case microphonePrimary = "ACT10"
    case microphoneSecondary = "ACT11"
    case assistant = "ACT12"

    var id: String { rawValue }
}

struct BridgeRequest: Codable, Sendable {
    let pairingCode: String
    let event: VibeEvent
    var prompt: String?
}

struct BridgeResponse: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case accepted
        case agentStatus
        case error
    }

    let kind: Kind
    var eventID: UUID?
    var agents: [VibeAgentState]?
    var message: String?

    static func accepted(_ eventID: UUID) -> BridgeResponse {
        BridgeResponse(kind: .accepted, eventID: eventID)
    }

    static func agentStatus(_ agents: [VibeAgentState]) -> BridgeResponse {
        BridgeResponse(kind: .agentStatus, agents: agents)
    }

    static func error(_ message: String) -> BridgeResponse {
        BridgeResponse(kind: .error, message: message)
    }
}

enum VibeEventPhase: Int, Codable, Sendable {
    case released = 0
    case pressed = 1
}

struct VibeEvent: Codable, Equatable, Identifiable, Sendable {
    static let reportLength = 63
    static let jsonRPCChannel: UInt8 = 2

    let id: UUID
    let key: String
    let phase: VibeEventPhase
    let createdAt: Date

    init(
        id: UUID = UUID(),
        key: String,
        phase: VibeEventPhase,
        createdAt: Date = .now
    ) {
        self.id = id
        self.key = key
        self.phase = phase
        self.createdAt = createdAt
    }

    static func agent(index: Int, phase: VibeEventPhase) -> VibeEvent {
        precondition((0..<6).contains(index))
        return VibeEvent(key: String(format: "AG%02d", index), phase: phase)
    }

    static func control(_ control: VibeControl, phase: VibeEventPhase) -> VibeEvent {
        VibeEvent(key: control.rawValue, phase: phase)
    }

    var jsonLine: String {
        #"{"m":"v.oai.hid","p":{"k":"\#(key)","act":\#(phase.rawValue)}}"# + "\r\n"
    }

    /// The same 63-byte vendor HID payload produced by the ESP32 firmware.
    var vendorReport: Data {
        let payload = Array(jsonLine.utf8)
        precondition(payload.count <= Self.reportLength - 2)

        var report = [UInt8](repeating: 0, count: Self.reportLength)
        report[0] = Self.jsonRPCChannel
        report[1] = UInt8(payload.count)
        report.replaceSubrange(2..<(2 + payload.count), with: payload)
        return Data(report)
    }

    var watchMessage: [String: Any] {
        [
            "type": "vibe-event",
            "id": id.uuidString,
            "key": key,
            "act": phase.rawValue,
            "createdAt": createdAt.timeIntervalSince1970,
            "report": vendorReport.base64EncodedString(),
        ]
    }

    init?(watchMessage: [String: Any]) {
        guard
            watchMessage["type"] as? String == "vibe-event",
            let idString = watchMessage["id"] as? String,
            let id = UUID(uuidString: idString),
            let key = watchMessage["key"] as? String,
            let act = watchMessage["act"] as? Int,
            let phase = VibeEventPhase(rawValue: act),
            let timestamp = watchMessage["createdAt"] as? TimeInterval
        else {
            return nil
        }

        self.init(
            id: id,
            key: key,
            phase: phase,
            createdAt: Date(timeIntervalSince1970: timestamp)
        )
    }
}

enum CodexCommand: Equatable, Sendable {
    case selectAgent(Int)
    case toggleFast
    case approve
    case reject
    case togglePlan
    case submit
    case microphone(active: Bool)
}

extension VibeEvent {
    var codexCommand: CodexCommand? {
        if key.hasPrefix("AG"),
           phase == .pressed,
           let index = Int(key.dropFirst(2)),
           (0..<6).contains(index) {
            return .selectAgent(index)
        }

        switch (key, phase) {
        case (VibeControl.fast.rawValue, .pressed):
            return .toggleFast
        case (VibeControl.ok.rawValue, .pressed):
            return .approve
        case (VibeControl.ng.rawValue, .pressed):
            return .reject
        case (VibeControl.plan.rawValue, .pressed):
            return .togglePlan
        case (VibeControl.assistant.rawValue, .pressed):
            return .submit
        case (VibeControl.microphonePrimary.rawValue, .pressed):
            return .microphone(active: true)
        case (VibeControl.microphonePrimary.rawValue, .released):
            return .microphone(active: false)
        default:
            return nil
        }
    }
}

struct VibeAgentState: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    var colorHex: UInt32
    var brightness: Double
    var effect: Int
    var speed: Double

    static let preview: [VibeAgentState] = [
        .init(id: 0, colorHex: 0xB07CFF, brightness: 1, effect: 1, speed: 0.8),
        .init(id: 1, colorHex: 0x5D6A87, brightness: 0.35, effect: 0, speed: 0),
        .init(id: 2, colorHex: 0x00D7FF, brightness: 0.85, effect: 4, speed: 0.6),
        .init(id: 3, colorHex: 0x50E890, brightness: 0.75, effect: 1, speed: 0.4),
        .init(id: 4, colorHex: 0xFFB020, brightness: 0.8, effect: 6, speed: 0.5),
        .init(id: 5, colorHex: 0x5D6A87, brightness: 0.25, effect: 0, speed: 0),
    ]
}
