import Foundation
import Observation

@MainActor
@Observable
final class BridgeController {
    enum ControlMode: String, CaseIterable, Identifiable {
        case accessibility = "Accessibility (Recommended)"
        case virtualHID = "Virtual HID (Experimental)"

        var id: String { rawValue }
    }

    private(set) var events: [VibeEvent] = []
    private(set) var serverState = "Stopped"
    private(set) var lastError: String?

    let pairingCode: String
    let accessibility = CodexAccessibilityController()
    let codex = CodexMicroTransport()
    var controlMode: ControlMode = .accessibility {
        didSet {
            if controlMode == .virtualHID { startVirtualHIDIfNeeded() }
        }
    }
    private var server: BridgeServer?

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

        let server = BridgeServer(pairingCode: pairingCode)
        server.onState = { [weak self] state in
            Task { @MainActor in self?.serverState = state }
        }
        server.onEvent = { [weak self] event in
            Task { @MainActor in self?.receive(event) }
        }
        self.server = server

        do {
            try server.start()
            accessibility.refresh()
        } catch {
            lastError = error.localizedDescription
            serverState = "Failed"
        }
    }

    private func receive(_ event: VibeEvent) {
        events.insert(event, at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }

        Task {
            do {
                switch controlMode {
                case .accessibility:
                    try accessibility.send(event)
                case .virtualHID:
                    try await codex.send(event)
                }
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func startVirtualHIDIfNeeded() {
        codex.start { [weak self] agents in
            Task { @MainActor in
                self?.server?.broadcast(.agentStatus(agents))
            }
        }
    }
}
