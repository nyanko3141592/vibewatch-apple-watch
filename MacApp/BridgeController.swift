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
    let codex = CodexAppServerTransport()
    let bleMicroPro = BLEMicroProTransport()
    private var server: BridgeServer?

    var isBridgeReady: Bool { serverState == "Ready" }
    var isHardwareReady: Bool { true }
    var isNativeHIDActive: Bool { codex.isReady }
    var isCodexRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty
    }
    var isReady: Bool { isBridgeReady && codex.isReady }
    var completedSetupSteps: Int {
        [isBridgeReady, codex.isReady, true].filter(\.self).count
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

        codex.start()

        let server = BridgeServer(pairingCode: pairingCode)
        server.onState = { [weak self] state in
            Task { @MainActor in self?.serverState = state }
        }
        server.onEvent = { [weak self] request, completion in
            Task { @MainActor in
                guard let self else {
                    completion("Bridge closed")
                    return
                }
                self.receive(request, completion: completion)
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
        if !codex.isReady { codex.start() }
        else if !codex.isBusy { codex.refreshThreads() }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for new Codex tasks"
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = codex.workspaceURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        codex.setWorkspace(url)
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
        } else if !codex.isReady {
            message = codex.detail
        } else {
            message = codex.detail
        }

        return BrowserStatus(
            connected: true,
            name: Host.current().localizedName ?? "Mac",
            message: message,
            bridgeReady: isBridgeReady,
            hardwareConnected: isHardwareReady,
            nativeHIDActive: isNativeHIDActive,
            codexRunning: codex.isReady,
            ready: isReady,
            codexBusy: codex.isBusy,
            pendingApproval: codex.hasPendingApproval,
            selectedAgent: codex.selectedAgent,
            fastMode: codex.fastMode,
            planMode: codex.planMode,
            newTaskMode: codex.creatingNewTask,
            lastResponse: codex.lastResponse,
            tasks: codex.recentThreads.map { BrowserTask(title: $0.title, cwd: $0.cwd, active: $0.isActive) },
            workspace: codex.workspaceURL.path,
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
        codexBusy: false,
        pendingApproval: false,
        selectedAgent: 1,
        fastMode: false,
        planMode: false,
        newTaskMode: false,
        lastResponse: "",
        tasks: [],
        workspace: "",
        lastError: "Bridge closed"
    )

    private func receive(
        _ request: BridgeRequest,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        let event = request.event
        events.insert(event, at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }

        do {
            guard event.phase == .pressed else {
                completion(nil)
                return
            }
            if event.key == "NEW00" {
                codex.prepareNewTask()
                lastError = nil
                completion(nil)
                return
            }
            switch event.codexCommand {
            case let .selectAgent(index): codex.selectAgent(index + 1)
            case .toggleFast: codex.toggleFast()
            case .approve: try codex.resolveApproval(accept: true)
            case .reject: try codex.resolveApproval(accept: false)
            case .togglePlan: codex.togglePlan()
            case .submit: try codex.submit(request.prompt ?? "")
            case .microphone: break
            case nil: break
            }
            lastError = nil
            completion(nil)
        } catch {
            lastError = error.localizedDescription
            completion(error.localizedDescription)
        }
    }
}
