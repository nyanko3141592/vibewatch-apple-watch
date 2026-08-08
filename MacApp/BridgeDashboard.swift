import SwiftUI

struct BridgeDashboard: View {
    @Bindable var controller: BridgeController

    var body: some View {
        NavigationStack {
            List {
                Section("Pair with iPhone") {
                    HStack {
                        Text("Pairing code")
                        Spacer()
                        Text(controller.pairingCode)
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                            .textSelection(.enabled)
                    }
                    LabeledContent("Network bridge", value: controller.serverState)
                    LabeledContent("Codex Micro HID", value: controller.codex.state.rawValue)
                }

                if let detail = controller.codex.detail {
                    Section("Codex connection") {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(controller.codex.state == .ready ? Color.secondary : Color.orange)
                    }
                }

                if let error = controller.lastError {
                    Section("Last error") {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section("Recent Watch events") {
                    if controller.events.isEmpty {
                        ContentUnavailableView(
                            "Waiting for Apple Watch",
                            systemImage: "applewatch.radiowaves.left.and.right",
                            description: Text("Open the Watch app and press a control.")
                        )
                    } else {
                        ForEach(controller.events) { event in
                            HStack {
                                Text(event.key).monospaced()
                                Spacer()
                                Text(event.phase == .pressed ? "DOWN" : "UP")
                                    .foregroundStyle(event.phase == .pressed ? .green : .secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Vibe Watch Bridge")
        }
    }
}
