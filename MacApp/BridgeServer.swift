@preconcurrency import Network
import Foundation

final class BridgeServer: @unchecked Sendable {
    var onState: (@Sendable (String) -> Void)?
    var onEvent: (@Sendable (VibeEvent) -> Void)?

    private let pairingCode: String
    private let queue = DispatchQueue(label: "com.nyanko3141592.VibeWatch.bridge-server")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: NWConnection] = [:]
    private var buffers: [ObjectIdentifier: Data] = [:]

    init(pairingCode: String) {
        self.pairingCode = pairingCode
    }

    func start() throws {
        let listener = try NWListener(using: .tcp)
        listener.service = NWListener.Service(name: "Vibe Watch Bridge", type: "_vibewatch._tcp")
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onState?("Ready")
            case let .failed(error): self?.onState?("Failed: \(error.localizedDescription)")
            case .waiting: self?.onState?("Waiting")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
        onState?("Starting")
    }

    func broadcast(_ response: BridgeResponse) {
        queue.async { [weak self] in
            guard let self else { return }
            for connection in clients.values { send(response, to: connection) }
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        clients[id] = connection
        buffers[id] = Data()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            if case .failed = state { remove(connection) }
            if case .cancelled = state { remove(connection) }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection else { return }
            if let data { consume(data, from: connection) }
            if complete || error != nil {
                remove(connection)
            } else {
                receive(on: connection)
            }
        }
    }

    private func consume(_ data: Data, from connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        buffers[id, default: Data()].append(data)
        while let newline = buffers[id]?.firstIndex(of: 0x0A) {
            guard let line = buffers[id]?[..<newline] else { break }
            buffers[id]?.removeSubrange(...newline)
            guard !line.isEmpty,
                  let request = try? JSONDecoder().decode(BridgeRequest.self, from: line)
            else {
                send(.error("Malformed bridge request"), to: connection)
                continue
            }
            guard request.pairingCode == pairingCode else {
                send(.error("Pairing code does not match"), to: connection)
                continue
            }
            onEvent?(request.event)
            send(.accepted(request.event.id), to: connection)
        }
    }

    private func send(_ response: BridgeResponse, to connection: NWConnection) {
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)
        connection.send(content: data, completion: .idempotent)
    }

    private func remove(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        clients.removeValue(forKey: id)
        buffers.removeValue(forKey: id)
        connection.cancel()
    }
}
