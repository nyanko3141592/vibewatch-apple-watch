@preconcurrency import Network
import Foundation
import Observation

@MainActor
@Observable
final class MacHostClient {
    enum State: String {
        case stopped
        case searching
        case connecting
        case connected
        case failed
    }

    private(set) var state: State = .stopped
    private(set) var hostName = ""
    private(set) var lastError: String?
    var pairingCode: String {
        didSet { UserDefaults.standard.set(pairingCode, forKey: Self.pairingCodeKey) }
    }

    var onAgentStatus: (([VibeAgentState]) -> Void)?

    private static let pairingCodeKey = "VibeWatchMacPairingCode"
    private let queue = DispatchQueue(label: "com.nyanko3141592.VibeWatch.mac-host")
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var receiveBuffer = Data()

    init() {
        pairingCode = UserDefaults.standard.string(forKey: Self.pairingCodeKey) ?? ""
    }

    func start() {
        guard browser == nil else { return }
        state = .searching
        lastError = nil

        let browser = NWBrowser(
            for: .bonjour(type: "_vibewatch._tcp", domain: nil),
            using: .tcp
        )
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handleBrowserState(state) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let endpoint = results.first?.endpoint else { return }
            Task { @MainActor in self?.connect(to: endpoint) }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        browser?.cancel()
        connection?.cancel()
        browser = nil
        connection = nil
        receiveBuffer.removeAll(keepingCapacity: true)
        state = .stopped
    }

    func send(_ event: VibeEvent) {
        guard let connection, state == .connected else {
            lastError = "Mac bridge is not connected"
            return
        }
        guard !pairingCode.isEmpty else {
            lastError = "Enter the pairing code shown on the Mac"
            return
        }

        do {
            var data = try JSONEncoder().encode(BridgeRequest(pairingCode: pairingCode, event: event))
            data.append(0x0A)
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.fail(error.localizedDescription) }
            })
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func connect(to endpoint: NWEndpoint) {
        guard connection == nil else { return }
        state = .connecting
        if case let .service(name, _, _, _) = endpoint { hostName = name }

        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in self?.handleConnectionState(newState) }
        }
        self.connection = connection
        connection.start(queue: queue)
        receiveNext(on: connection)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                if let data { self.consume(data) }
                if let error {
                    self.fail(error.localizedDescription)
                } else if complete {
                    self.fail("Mac bridge disconnected")
                } else {
                    self.receiveNext(on: connection)
                }
            }
        }
    }

    private func consume(_ data: Data) {
        receiveBuffer.append(data)
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let line = receiveBuffer[..<newline]
            receiveBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let response = try? JSONDecoder().decode(BridgeResponse.self, from: line)
            else { continue }

            switch response.kind {
            case .accepted:
                lastError = nil
            case .agentStatus:
                if let agents = response.agents { onAgentStatus?(agents) }
            case .error:
                lastError = response.message
            }
        }
    }

    private func handleBrowserState(_ newState: NWBrowser.State) {
        if case let .failed(error) = newState { fail(error.localizedDescription) }
    }

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            state = .connected
            lastError = nil
        case let .failed(error):
            fail(error.localizedDescription)
        case .cancelled:
            if state != .stopped { state = .searching }
            connection = nil
        default:
            break
        }
    }

    private func fail(_ message: String) {
        lastError = message
        state = .failed
        connection?.cancel()
        connection = nil
    }
}
