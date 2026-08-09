@preconcurrency import Network
import Foundation

final class BridgeServer: @unchecked Sendable {
    var onState: (@Sendable (String) -> Void)?
    var onEvent: (@Sendable (VibeEvent, @escaping @Sendable (String?) -> Void) -> Void)?
    var onBrowserStatus: (@Sendable (@escaping @Sendable (BrowserStatus) -> Void) -> Void)?

    private let pairingCode: String
    private let queue = DispatchQueue(label: "com.nyanko3141592.VibeWatch.bridge-server")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: NWConnection] = [:]
    private var buffers: [ObjectIdentifier: Data] = [:]

    static let port = NWEndpoint.Port(rawValue: 8360)!

    init(pairingCode: String) {
        self.pairingCode = pairingCode
    }

    func start() throws {
        let listener = try NWListener(using: .tcp, on: Self.port)
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
            if let data, consume(data, from: connection) { return }
            if complete || error != nil {
                remove(connection)
            } else {
                receive(on: connection)
            }
        }
    }

    @discardableResult
    private func consume(_ data: Data, from connection: NWConnection) -> Bool {
        let id = ObjectIdentifier(connection)
        buffers[id, default: Data()].append(data)

        if isHTTPRequest(buffers[id] ?? Data()) {
            return consumeHTTPRequest(from: connection)
        }

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
            onEvent?(request.event) { _ in }
            send(.accepted(request.event.id), to: connection)
        }
        return false
    }

    private func isHTTPRequest(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(8), encoding: .utf8) else { return false }
        return prefix.hasPrefix("GET ") || prefix.hasPrefix("POST ") || prefix.hasPrefix("OPTIONS ")
    }

    private func consumeHTTPRequest(from connection: NWConnection) -> Bool {
        let id = ObjectIdentifier(connection)
        guard let data = buffers[id],
              let headerRange = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else { return false }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return false }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            sendHTTP(status: 400, body: Data("Bad Request".utf8), type: "text/plain", to: connection)
            return true
        }

        let method = String(requestParts[0])
        let target = String(requestParts[1])
        let contentLength = lines.dropFirst().compactMap { line -> Int? in
            let components = line.split(separator: ":", maxSplits: 1)
            guard components.count == 2,
                  components[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
            else { return nil }
            return Int(components[1].trimmingCharacters(in: .whitespaces))
        }.first ?? 0

        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return false }
        let body = Data(data[bodyStart..<(bodyStart + contentLength)])
        buffers[id] = Data()

        routeHTTP(method: method, target: target, body: body, connection: connection)
        return true
    }

    private func routeHTTP(
        method: String,
        target: String,
        body: Data,
        connection: NWConnection
    ) {
        guard let components = URLComponents(string: "http://vibewatch.local\(target)") else {
            sendHTTP(status: 400, body: Data("Bad Request".utf8), type: "text/plain", to: connection)
            return
        }

        if method == "GET", components.path == "/" || components.path == "/controller" {
            guard let html = BrowserControllerPage.html.data(using: .utf8) else {
                sendHTTP(status: 500, body: Data(), type: "text/plain", to: connection)
                return
            }
            sendHTTP(status: 200, body: html, type: "text/html; charset=utf-8", to: connection)
            return
        }

        if method == "GET", components.path == "/api/status" {
            guard queryValue("code", in: components) == pairingCode else {
                sendJSON(BridgeResponse.error("Pairing code does not match"), status: 403, to: connection)
                return
            }
            guard let onBrowserStatus else {
                sendJSON(BridgeResponse.error("Bridge is still starting"), status: 503, to: connection)
                return
            }
            onBrowserStatus { [weak self, weak connection] status in
                guard let self, let connection else { return }
                self.queue.async { self.sendJSON(status, status: 200, to: connection) }
            }
            return
        }

        if method == "POST", components.path == "/api/event" {
            guard let request = try? JSONDecoder().decode(BridgeRequest.self, from: body) else {
                sendJSON(BridgeResponse.error("Malformed event"), status: 400, to: connection)
                return
            }
            guard request.pairingCode == pairingCode else {
                sendJSON(BridgeResponse.error("Pairing code does not match"), status: 403, to: connection)
                return
            }
            guard let onEvent else {
                sendJSON(BridgeResponse.error("Bridge is not ready"), status: 503, to: connection)
                return
            }
            onEvent(request.event) { [weak self, weak connection] errorMessage in
                guard let self, let connection else { return }
                self.queue.async {
                    if let errorMessage {
                        self.sendJSON(BridgeResponse.error(errorMessage), status: 422, to: connection)
                    } else {
                        self.sendJSON(BridgeResponse.accepted(request.event.id), status: 200, to: connection)
                    }
                }
            }
            return
        }

        sendHTTP(status: 404, body: Data("Not Found".utf8), type: "text/plain", to: connection)
    }

    private func queryValue(_ name: String, in components: URLComponents) -> String? {
        components.queryItems?.first(where: { $0.name == name })?.value
    }

    private func sendJSON<T: Encodable>(_ value: T, status: Int, to connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(value) else {
            sendHTTP(status: 500, body: Data(), type: "application/json", to: connection)
            return
        }
        sendHTTP(status: status, body: data, type: "application/json", to: connection)
    }

    private func sendHTTP(
        status: Int,
        body: Data,
        type: String,
        to connection: NWConnection
    ) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 422: reason = "Unprocessable Content"
        case 503: reason = "Service Unavailable"
        default: reason = "Internal Server Error"
        }
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self, weak connection] _ in
            guard let self, let connection else { return }
            self.queue.async { self.remove(connection) }
        })
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

struct BrowserStatus: Codable, Sendable {
    let connected: Bool
    let name: String
    let message: String
    let bridgeReady: Bool
    let hardwareConnected: Bool
    let nativeHIDActive: Bool
    let codexRunning: Bool
    let ready: Bool
    let lastError: String?
}
