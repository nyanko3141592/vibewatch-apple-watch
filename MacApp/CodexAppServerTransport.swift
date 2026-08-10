import Foundation
import Observation

@MainActor
@Observable
final class CodexAppServerTransport {
    private(set) var isReady = false
    private(set) var isBusy = false
    private(set) var hasPendingApproval = false
    private(set) var detail = "Starting Codex app-server…"
    private(set) var lastResponse = ""
    private(set) var selectedAgent = 1
    private(set) var fastMode = false
    private(set) var planMode = false

    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var threadID: String?
    private var turnID: String?
    private var pendingApprovalID: Any?
    private var requestID = 10
    private var queuedPrompt: String?

    func start() {
        guard process == nil else { return }
        guard let executable = Self.codexExecutable else {
            detail = "Codex CLI was not found. Install or update the Codex desktop app."
            return
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.isReady = false
                self?.isBusy = false
                self?.detail = "Codex app-server stopped (exit \(process.terminationStatus))."
                self?.process = nil
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consume(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let message = String(data: data, encoding: .utf8), !message.isEmpty else { return }
            Task { @MainActor in self?.detail = message.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        do {
            try process.run()
            self.process = process
            input = stdin.fileHandleForWriting
            send([
                "method": "initialize", "id": 1,
                "params": [
                    "clientInfo": ["name": "vibewatch_bridge", "title": "Vibe Watch Bridge", "version": "0.4.0"],
                    "capabilities": ["experimentalApi": true],
                ],
            ])
        } catch {
            detail = error.localizedDescription
            self.process = nil
        }
    }

    func selectAgent(_ index: Int) {
        selectedAgent = min(max(index, 1), 6)
        detail = "Agent \(selectedAgent) selected. Enter an instruction and tap Send."
    }

    func toggleFast() {
        fastMode.toggle()
        detail = fastMode ? "Fast mode on." : "Fast mode off."
    }

    func togglePlan() {
        planMode.toggle()
        detail = planMode ? "Plan-first mode on." : "Plan-first mode off."
    }

    func submit(_ prompt: String) throws {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TransportError.emptyPrompt }
        guard process != nil else { throw TransportError.notRunning }

        let instruction = modePrefix + trimmed
        if threadID == nil {
            queuedPrompt = instruction
            startThread()
        } else if isBusy, let threadID {
            sendRequest(method: "turn/steer", params: [
                "threadId": threadID,
                "input": [["type": "text", "text": instruction]],
            ])
            detail = "Instruction added to the active Codex turn."
        } else {
            startTurn(instruction)
        }
    }

    func resolveApproval(accept: Bool) throws {
        guard let id = pendingApprovalID else { throw TransportError.noApproval }
        send(["id": id, "result": ["decision": accept ? "accept" : "decline"]])
        pendingApprovalID = nil
        hasPendingApproval = false
        detail = accept ? "Approved. Codex is continuing." : "Rejected. Codex is continuing without that action."
    }

    func interrupt() throws {
        guard let threadID, let turnID, isBusy else { throw TransportError.noActiveTurn }
        sendRequest(method: "turn/interrupt", params: ["threadId": threadID, "turnId": turnID])
        detail = "Stopping the active Codex turn…"
    }

    private var modePrefix: String {
        let roles = [
            "Primary implementation agent", "Code reviewer", "Debugging specialist",
            "Test engineer", "UI/UX specialist", "Release and documentation agent",
        ]
        var parts = ["Act as \(roles[selectedAgent - 1])."]
        if fastMode { parts.append("Prioritize speed and make reasonable assumptions.") }
        if planMode { parts.append("State a concise plan before implementation.") }
        return parts.joined(separator: " ") + "\n\n"
    }

    private func startThread() {
        detail = "Creating a Codex task…"
        sendRequest(method: "thread/start", id: 2, params: [
            "cwd": FileManager.default.homeDirectoryForCurrentUser.path,
            "approvalPolicy": "on-request",
            "sandbox": "workspace-write",
        ])
    }

    private func startTurn(_ prompt: String) {
        guard let threadID else { return }
        lastResponse = ""
        isBusy = true
        detail = "Codex is working…"
        sendRequest(method: "turn/start", params: [
            "threadId": threadID,
            "input": [["type": "text", "text": prompt]],
        ])
    }

    private func sendRequest(method: String, id: Int? = nil, params: [String: Any]) {
        let id = id ?? nextID()
        send(["method": method, "id": id, "params": params])
    }

    private func nextID() -> Int {
        defer { requestID += 1 }
        return requestID
    }

    private func send(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object)
        else { return }
        data.append(0x0A)
        try? input?.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(object)
        }
    }

    private func handle(_ object: [String: Any]) {
        if (object["id"] as? NSNumber)?.intValue == 1, object["result"] != nil {
            send(["method": "initialized", "params": [:]])
            isReady = true
            detail = "Software connection ready — no BLE device required."
            return
        }
        if (object["id"] as? NSNumber)?.intValue == 2,
           let result = object["result"] as? [String: Any],
           let thread = result["thread"] as? [String: Any],
           let id = thread["id"] as? String {
            threadID = id
            if let prompt = queuedPrompt {
                queuedPrompt = nil
                startTurn(prompt)
            }
            return
        }

        guard let method = object["method"] as? String else {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                detail = message
                isBusy = false
            }
            return
        }
        let params = object["params"] as? [String: Any]
        switch method {
        case "turn/started":
            if let turn = params?["turn"] as? [String: Any] { turnID = turn["id"] as? String }
            isBusy = true
            detail = "Codex is working…"
        case "item/agentMessage/delta":
            if let delta = params?["delta"] as? String { lastResponse += delta }
        case "turn/completed":
            isBusy = false
            turnID = nil
            detail = "Codex completed the instruction."
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval", "permissions/requestApproval":
            pendingApprovalID = object["id"]
            hasPendingApproval = true
            detail = "Codex is waiting for Approve or Reject."
        case "serverRequest/resolved":
            pendingApprovalID = nil
            hasPendingApproval = false
        default:
            break
        }
    }

    private static var codexExecutable: URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    enum TransportError: LocalizedError {
        case emptyPrompt, notRunning, noApproval, noActiveTurn
        var errorDescription: String? {
            switch self {
            case .emptyPrompt: "Enter or dictate an instruction before pressing Send."
            case .notRunning: "Codex app-server is not running."
            case .noApproval: "Codex is not waiting for an approval."
            case .noActiveTurn: "There is no active Codex turn to stop."
            }
        }
    }
}
