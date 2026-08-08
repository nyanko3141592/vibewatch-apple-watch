@preconcurrency import WatchConnectivity
import Foundation
import Observation

@MainActor
@Observable
final class PhoneRelay: NSObject {
    enum State: String {
        case unsupported
        case activating
        case waitingForWatch
        case connected
    }

    private(set) var state: State = .activating
    private(set) var events: [VibeEvent] = []
    var agents = VibeAgentState.preview
    let macHost = MacHostClient()
    var macPairingCode: String {
        get { macHost.pairingCode }
        set { macHost.pairingCode = newValue }
    }

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    func activate() {
        macHost.onAgentStatus = { [weak self] agents in
            guard let self else { return }
            self.agents = agents
            self.sendAgentState()
        }
        macHost.start()
        guard let session else {
            state = .unsupported
            return
        }
        session.delegate = self
        session.activate()
        refreshState()
    }

    func sendPreviewAgentState() {
        sendAgentState()
    }

    private func sendAgentState() {
        guard let session,
              let data = try? JSONEncoder().encode(agents)
        else { return }

        let message: [String: Any] = [
            "type": "agent-status",
            "agents": data.base64EncodedString(),
        ]
        try? session.updateApplicationContext(message)
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    private func receive(_ event: VibeEvent) {
        events.insert(event, at: 0)
        if events.count > 50 { events.removeLast(events.count - 50) }

        macHost.send(event)
    }

    private func refreshState() {
        guard let session else {
            state = .unsupported
            return
        }
        guard session.activationState == .activated else {
            state = .activating
            return
        }
        state = session.isReachable ? .connected : .waitingForWatch
    }
}

extension PhoneRelay: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let event = VibeEvent(watchMessage: message) else { return }
        Task { @MainActor in self.receive(event) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let event = VibeEvent(watchMessage: userInfo) else { return }
        Task { @MainActor in self.receive(event) }
    }
}
