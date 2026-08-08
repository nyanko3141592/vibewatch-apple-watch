import AppKit
import ApplicationServices
import Foundation
import Observation

@MainActor
@Observable
final class CodexAccessibilityController {
    enum State: String {
        case accessRequired = "Accessibility permission required"
        case codexNotRunning = "Codex is not running"
        case ready = "Ready"
        case failed = "Failed"
    }

    private(set) var state: State = .accessRequired
    private(set) var detail = "Allow Vibe Watch Bridge in System Settings → Privacy & Security → Accessibility."

    var isTrusted: Bool { AXIsProcessTrusted() }

    func refresh() {
        guard AXIsProcessTrusted() else {
            state = .accessRequired
            detail = "No restricted Apple entitlement is needed. One standard Accessibility permission is required."
            return
        }
        guard Self.codexApplication != nil else {
            state = .codexNotRunning
            detail = "Open the ChatGPT/Codex desktop app, then press Refresh."
            return
        }
        state = .ready
        detail = "iPhone and Apple Watch controls are routed to the visible Codex interface."
    }

    func requestAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        refresh()
    }

    func send(_ event: VibeEvent) throws {
        guard let command = event.codexCommand else { return }
        guard AXIsProcessTrusted() else {
            refresh()
            throw AccessibilityError.permissionRequired
        }
        guard let application = Self.codexApplication else {
            refresh()
            throw AccessibilityError.codexNotRunning
        }

        application.activate()
        let root = AXUIElementCreateApplication(application.processIdentifier)

        switch command {
        case let .selectAgent(index):
            try selectAgent(index, in: root)
        case .toggleFast:
            try pressControl(matching: ["fast", "高速"], in: root, command: "FAST")
        case .approve:
            try pressControl(
                matching: ["approve", "allow", "承認", "許可"],
                in: root,
                command: "Approve"
            )
        case .reject:
            try pressControl(
                matching: ["reject", "decline", "deny", "拒否", "却下"],
                in: root,
                command: "Reject"
            )
        case .togglePlan:
            try pressControl(matching: ["plan", "プラン"], in: root, command: "Plan")
        case .submit:
            if !pressFirst(matching: ["send", "submit", "送信"], in: root) {
                postReturnKey()
            }
        case .microphone:
            try pressControl(
                matching: ["push to talk", "microphone", "voice", "マイク", "音声"],
                in: root,
                command: "Microphone"
            )
        }
        state = .ready
    }

    private func pressControl(matching terms: [String], in root: AXUIElement, command: String) throws {
        guard pressFirst(matching: terms, in: root) else {
            state = .failed
            detail = "Could not find the \(command) control in the current Codex screen."
            throw AccessibilityError.controlNotFound(command)
        }
    }

    private func pressFirst(matching terms: [String], in root: AXUIElement) -> Bool {
        let normalizedTerms = terms.map { $0.lowercased() }
        let elements = flatten(root)
        let candidates = elements.compactMap { element -> (AXUIElement, String, String)? in
            let role = stringAttribute(kAXRoleAttribute, of: element) ?? ""
            let label = searchableText(of: element).lowercased()
            guard !label.isEmpty, normalizedTerms.contains(where: label.contains) else { return nil }
            return (element, role, label)
        }
        .sorted { lhs, rhs in
            score(role: lhs.1, label: lhs.2, terms: normalizedTerms)
                > score(role: rhs.1, label: rhs.2, terms: normalizedTerms)
        }

        for candidate in candidates where performPress(candidate.0) { return true }
        return false
    }

    private func selectAgent(_ index: Int, in root: AXUIElement) throws {
        let ignored = ["settings", "search", "new chat", "設定", "検索", "新しいチャット"]
        let taskButtons = flatten(root).filter { element in
            guard stringAttribute(kAXRoleAttribute, of: element) == kAXButtonRole as String,
                  let title = stringAttribute(kAXTitleAttribute, of: element)?.lowercased(),
                  title.count >= 2,
                  !ignored.contains(where: title.contains)
            else { return false }
            return containsChatActions(element)
        }

        guard taskButtons.indices.contains(index), performPress(taskButtons[index]) else {
            state = .failed
            detail = "Could not select Codex task \(index + 1). Keep the target tasks visible in the sidebar."
            throw AccessibilityError.controlNotFound("Agent \(index + 1)")
        }
    }

    private func containsChatActions(_ element: AXUIElement) -> Bool {
        let actionTerms = ["pin chat", "archive chat", "チャットをピン留め", "チャットをアーカイブ"]
        return flatten(element, maximumDepth: 6, maximumCount: 80).contains { descendant in
            let label = searchableText(of: descendant).lowercased()
            return actionTerms.contains(where: label.contains)
        }
    }

    private func flatten(
        _ root: AXUIElement,
        maximumDepth: Int = 36,
        maximumCount: Int = 12_000
    ) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var visited = Set<CFHashCode>()

        while let (element, depth) = pending.popLast(), result.count < maximumCount {
            let hash = CFHash(element)
            guard visited.insert(hash).inserted else { continue }
            result.append(element)
            guard depth < maximumDepth else { continue }
            let children = elementsAttribute(kAXChildrenAttribute, of: element)
            pending.append(contentsOf: children.reversed().map { ($0, depth + 1) })
        }
        return result
    }

    private func searchableText(of element: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute]
            .compactMap { stringAttribute($0, of: element) }
            .joined(separator: " ")
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func elementsAttribute(_ name: String, of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func performPress(_ element: AXUIElement) -> Bool {
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success { return true }
        for child in elementsAttribute(kAXChildrenAttribute, of: element) {
            if AXUIElementPerformAction(child, kAXPressAction as CFString) == .success { return true }
        }
        return false
    }

    private func score(role: String, label: String, terms: [String]) -> Int {
        var value = role == kAXButtonRole as String || role == kAXMenuItemRole as String ? 100 : 0
        if terms.contains(label) { value += 50 }
        value -= label.count
        return value
    }

    private func postReturnKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private static var codexApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first
    }
}

private enum AccessibilityError: LocalizedError {
    case permissionRequired
    case codexNotRunning
    case controlNotFound(String)

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            "Accessibility permission is required"
        case .codexNotRunning:
            "ChatGPT/Codex is not running"
        case let .controlNotFound(control):
            "Codex control not found: \(control)"
        }
    }
}
