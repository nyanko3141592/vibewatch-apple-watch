@preconcurrency import WatchConnectivity
import Foundation
import Observation

@MainActor
@Observable
final class WatchLink: NSObject {
    enum State: String {
        case unsupported
        case activating
        case connected
        case queued
    }

    private(set) var state: State = .activating
    private(set) var lastEvent: VibeEvent?
    var agents = VibeAgentState.preview

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    func activate() {
        guard let session else {
            state = .unsupported
            return
        }
        session.delegate = self
        session.activate()
        refreshState()
    }

    func send(_ event: VibeEvent) {
        lastEvent = event
        guard let session, session.activationState == .activated else {
            state = .queued
            return
        }

        if session.isReachable {
            state = .connected
            session.sendMessage(event.watchMessage, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in self?.queue(event, on: session) }
            }
        } else {
            queue(event, on: session)
        }
    }

    private func queue(_ event: VibeEvent, on session: WCSession) {
        state = .queued
        session.transferUserInfo(event.watchMessage)
    }

    private func refreshState() {
        guard let session else {
            state = .unsupported
            return
        }
        switch session.activationState {
        case .activated:
            state = session.isReachable ? .connected : .queued
        case .inactive, .notActivated:
            state = .activating
        @unknown default:
            state = .activating
        }
    }

    nonisolated private static func decodeAgentMessage(_ message: [String: Any]) -> [VibeAgentState]? {
        guard
            message["type"] as? String == "agent-status",
            let dataString = message["agents"] as? String,
            let data = Data(base64Encoded: dataString),
            let decoded = try? JSONDecoder().decode([VibeAgentState].self, from: data)
        else {
            return nil
        }
        return decoded
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let decoded = Self.decodeAgentMessage(message) else { return }
        Task { @MainActor in self.agents = decoded }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let decoded = Self.decodeAgentMessage(applicationContext) else { return }
        Task { @MainActor in self.agents = decoded }
    }
}
