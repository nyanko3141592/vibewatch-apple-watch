import Foundation
import Observation

@MainActor
@Observable
final class BridgeController {
    private(set) var events: [VibeEvent] = []
    private(set) var serverState = "Stopped"
    private(set) var lastError: String?

    let pairingCode: String
    let codex = CodexMicroTransport()
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
            codex.start { [weak self] agents in
                Task { @MainActor in
                    self?.server?.broadcast(.agentStatus(agents))
                }
            }
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
                try await codex.send(event)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
