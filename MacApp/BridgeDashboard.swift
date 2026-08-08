import SwiftUI

struct BridgeDashboard: View {
    @Bindable var controller: BridgeController

    var body: some View {
        NavigationStack {
            List {
                Section("Pair with iPhone") {
                    if let url = controller.browserURL {
                        HStack(alignment: .center, spacing: 20) {
                            QRCodeView(value: url.absoluteString)
                                .frame(width: 132, height: 132)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Scan with the iPhone camera")
                                    .font(.headline)
                                Text("No iPhone app required")
                                    .foregroundStyle(.secondary)
                                Text("Tap controls; hold only the microphone")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(url.absoluteString)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    HStack {
                        Text("Pairing code")
                        Spacer()
                        Text(controller.pairingCode)
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                            .textSelection(.enabled)
                    }
                    LabeledContent("Network bridge", value: controller.serverState)
                }

                Section("Codex control") {
                    Picker("Mode", selection: $controller.controlMode) {
                        ForEach(BridgeController.ControlMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    if controller.controlMode == .accessibility {
                        LabeledContent("Status", value: controller.accessibility.state.rawValue)
                        Text(controller.accessibility.detail)
                            .font(.callout)
                            .foregroundStyle(controller.accessibility.state == .ready ? Color.secondary : Color.orange)
                        HStack {
                            Button("Grant Accessibility Access") {
                                controller.accessibility.requestAccess()
                            }
                            Button("Refresh") {
                                controller.accessibility.refresh()
                            }
                        }
                    } else {
                        LabeledContent("Codex Micro HID", value: controller.codex.state.rawValue)
                        if let detail = controller.codex.detail {
                            Text(detail)
                                .font(.callout)
                                .foregroundStyle(controller.codex.state == .ready ? Color.secondary : Color.orange)
                        }
                    }
                }

                if let error = controller.lastError {
                    Section("Last error") {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section("Recent control events") {
                    if controller.events.isEmpty {
                        ContentUnavailableView(
                            "Waiting for iPhone or Apple Watch",
                            systemImage: "iphone.and.arrow.forward.inward",
                            description: Text("Scan the QR code with your iPhone and tap a control.")
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
