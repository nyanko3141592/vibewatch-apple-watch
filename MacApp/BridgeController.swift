import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class BridgeController {
    private(set) var events: [VibeEvent] = []
    private(set) var serverState = "Stopped"
    private(set) var lastError: String?

    let pairingCode: String
    let bleMicroPro = BLEMicroProTransport()
    private var server: BridgeServer?

    var isBridgeReady: Bool { serverState == "Ready" }
    var isHardwareReady: Bool { bleMicroPro.isConnected }
    var isNativeHIDActive: Bool { bleMicroPro.hostHandshakeReceived }
    var isCodexRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty
    }
    var isReady: Bool { isBridgeReady && isHardwareReady && isCodexRunning }
    var completedSetupSteps: Int {
        [isBridgeReady, isHardwareReady, isCodexRunning].filter(\.self).count
    }

    var browserURL: URL? {
        let host = LocalNetworkAddress.ipv4 ?? Self.localHostName
        return URL(string: "http://\(host):\(BridgeServer.port.rawValue)/?code=\(pairingCode)")
    }

    private static var localHostName: String {
        var host = ProcessInfo.processInfo.hostName
        if !host.hasSuffix(".local") { host += ".local" }
        return host
    }

    init() {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "VibeWatchPairingCode") {
            pairingCode = existing
        } else {
            let generated = String(format: "%06d", Int.random(in: 0...999_999))
            defaults.set(generated, forKey: "VibeWatchPairingCode")
            pairingCode = generated
        }
    }

    func start() {
        guard server == nil else { return }

        bleMicroPro.start { [weak self] agents in
            self?.server?.broadcast(.agentStatus(agents))
        }

        let server = BridgeServer(pairingCode: pairingCode)
        server.onState = { [weak self] state in
            Task { @MainActor in self?.serverState = state }
        }
        server.onEvent = { [weak self] event, completion in
            Task { @MainActor in
                guard let self else {
                    completion("Bridge closed")
                    return
                }
                self.receive(event, completion: completion)
            }
        }
        server.onBrowserStatus = { [weak self] completion in
            Task { @MainActor in
                completion(self?.browserStatus ?? Self.unavailableBrowserStatus)
            }
        }
        self.server = server

        do {
            try server.start()
        } catch {
            lastError = error.localizedDescription
            serverState = "Failed"
        }
    }

    func refreshSetup() {
        if !bleMicroPro.isConnected { bleMicroPro.rescan() }
    }

    func openCodex() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else {
            lastError = "Codex is not installed in Applications."
        }
    }

    private var browserStatus: BrowserStatus {
        let message: String
        if !isBridgeReady {
            message = "The Mac bridge is still starting."
        } else if !isHardwareReady {
            message = bleMicroPro.detail
        } else if !isCodexRunning {
            message = "Open Codex on your Mac."
        } else if !isNativeHIDActive {
            message = "BLE HID is connected. Codex has not sent its first native status frame yet."
        } else {
            message = "Ready — controls use the native Codex Micro BLE HID protocol."
        }

        return BrowserStatus(
            connected: true,
            name: Host.current().localizedName ?? "Mac",
            message: message,
            bridgeReady: isBridgeReady,
            hardwareConnected: isHardwareReady,
            nativeHIDActive: isNativeHIDActive,
            codexRunning: isCodexRunning,
            ready: isReady,
            lastError: lastError
        )
    }

    private static let unavailableBrowserStatus = BrowserStatus(
        connected: false,
        name: "Mac",
        message: "The Mac bridge closed.",
        bridgeReady: false,
        hardwareConnected: false,
        nativeHIDActive: false,
        codexRunning: false,
        ready: false,
        lastError: "Bridge closed"
    )

    private func receive(
        _ event: VibeEvent,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        events.insert(event, at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }

        do {
            try bleMicroPro.send(event)
            lastError = nil
            completion(nil)
        } catch {
            lastError = error.localizedDescription
            completion(error.localizedDescription)
        }
    }
}
