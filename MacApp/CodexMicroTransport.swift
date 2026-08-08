import CoreHID
import Foundation
import Observation

@MainActor
@Observable
final class CodexMicroTransport {
    enum State: String {
        case stopped
        case unavailable
        case ready
        case failed
    }

    private(set) var state: State = .stopped
    private(set) var detail: String?

    private var device: HIDVirtualDevice?
    private var deviceDelegate: CodexMicroDeviceDelegate?

    func start(onAgentStatus: @escaping @Sendable ([VibeAgentState]) -> Void) {
        guard device == nil else { return }

        let properties = HIDVirtualDevice.Properties(
            descriptor: Self.reportDescriptor,
            vendorID: 0x303A,
            productID: 0x8360,
            transport: .usb,
            product: "Codex Micro",
            manufacturer: "VibeWatch",
            modelNumber: "Codex Micro",
            versionNumber: 1,
            serialNumber: "VIBE-WATCH-BRIDGE"
        )
        guard let device = HIDVirtualDevice(properties: properties) else {
            state = .unavailable
            detail = "macOS refused to create the virtual Codex Micro. Sign this target with the com.apple.developer.hid.virtual.device entitlement."
            return
        }

        let delegate = CodexMicroDeviceDelegate(onAgentStatus: onAgentStatus)
        self.device = device
        self.deviceDelegate = delegate
        Task {
            await device.activate(delegate: delegate)
            state = .ready
            detail = "ChatGPT/Codex sees this bridge as Vendor 0x303A, Product 0x8360."
        }
    }

    func send(_ event: VibeEvent) async throws {
        guard let device, state == .ready else {
            throw CodexMicroError.notReady
        }
        try await device.dispatchInputReport(
            data: Data([6]) + event.vendorReport,
            timestamp: SuspendingClock.now
        )
    }

    private static let reportDescriptor = Data([
        0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x85, 0x06,
        0x09, 0x02, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08,
        0x95, 0x3F, 0x81, 0x02,
        0x09, 0x03, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08,
        0x95, 0x3F, 0x91, 0x02,
        0x09, 0x04, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08,
        0x95, 0x3F, 0xB1, 0x02,
        0xC0,
    ])
}

private actor CodexMicroDeviceDelegate: HIDVirtualDeviceDelegate {
    private let onAgentStatus: @Sendable ([VibeAgentState]) -> Void
    private var rpcBuffer = Data()

    init(onAgentStatus: @escaping @Sendable ([VibeAgentState]) -> Void) {
        self.onAgentStatus = onAgentStatus
    }

    func hidVirtualDevice(
        _ device: HIDVirtualDevice,
        receivedSetReportRequestOfType type: HIDReportType,
        id: HIDReportID?,
        data: Data
    ) async throws {
        var report = data
        if report.first == 6, report.count >= 64 { report.removeFirst() }
        guard report.count >= 2, report[0] == VibeEvent.jsonRPCChannel else { return }
        let count = min(Int(report[1]), max(0, report.count - 2))
        rpcBuffer.append(report[2..<(2 + count)])
        guard let object = try? JSONSerialization.jsonObject(with: rpcBuffer) as? [String: Any] else {
            return
        }
        rpcBuffer.removeAll(keepingCapacity: true)
        await process(object, on: device)
    }

    func hidVirtualDevice(
        _ device: HIDVirtualDevice,
        receivedGetReportRequestOfType type: HIDReportType,
        id: HIDReportID?,
        maxSize: Int
    ) async throws -> Data {
        Data(repeating: 0, count: min(VibeEvent.reportLength, maxSize))
    }

    private func process(_ request: [String: Any], on device: HIDVirtualDevice) async {
        let method = (request["method"] ?? request["m"]) as? String ?? ""
        let params = request["params"] ?? request["p"]
        if method == "v.oai.thstatus", let values = params as? [[String: Any]] {
            let agents = values.compactMap { item -> VibeAgentState? in
                guard let id = item["id"] as? Int else { return nil }
                return VibeAgentState(
                    id: id,
                    colorHex: UInt32(item["c"] as? Int ?? 0),
                    brightness: item["b"] as? Double ?? 0,
                    effect: item["e"] as? Int ?? 0,
                    speed: item["s"] as? Double ?? 0
                )
            }
            onAgentStatus(agents)
        }

        let id = (request["id"] ?? request["i"]) as? Int
        guard let id, !method.isEmpty else { return }

        var result: [String: Any] = ["ok": 1]
        if method == "device.status" {
            result = [
                "version": "v1.0",
                "profile_index": 0,
                "layer_index": 1,
                "battery": 100,
                "is_charging": true,
            ]
        } else if method == "sys.version" {
            result = ["version": "v1.0"]
        }

        let response: [String: Any] = ["id": id, "method": method, "result": result]
        guard let json = try? JSONSerialization.data(withJSONObject: response) else { return }
        var payload = json
        payload.append(contentsOf: [0x0D, 0x0A])

        var offset = 0
        while offset < payload.count {
            let chunkCount = min(61, payload.count - offset)
            var frame = Data([6, VibeEvent.jsonRPCChannel, UInt8(chunkCount)])
            frame.append(payload[offset..<(offset + chunkCount)])
            frame.append(Data(repeating: 0, count: 64 - frame.count))
            try? await device.dispatchInputReport(data: frame, timestamp: SuspendingClock.now)
            offset += chunkCount
        }
    }
}

private enum CodexMicroError: LocalizedError {
    case notReady

    var errorDescription: String? {
        "Virtual Codex Micro is not ready"
    }
}
