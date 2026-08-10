import SwiftUI

struct BridgeDashboard: View {
    @Bindable var controller: BridgeController

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetupSummary(controller: controller)
                }

                Section("First-time setup") {
                    SetupStepRow(
                        number: 1,
                        isComplete: controller.isBridgeReady,
                        title: "Mac bridge",
                        detail: controller.isBridgeReady ? "Listening on your local network" : "Starting the local controller"
                    )

                    SetupStepRow(
                        number: 2,
                        isComplete: controller.codex.isReady,
                        title: "Codex app-server",
                        detail: controller.codex.detail,
                        actionTitle: controller.codex.isReady ? nil : "Retry"
                    ) {
                        controller.codex.start()
                    }

                    SetupStepRow(
                        number: 3,
                        isComplete: true,
                        title: "No hardware required",
                        detail: "Instructions go directly to Codex through its official local interface"
                    )
                }

                Section(controller.isReady ? "Connect your iPhone" : "Your iPhone") {
                    QRConnectPanel(controller: controller)
                }

                if let error = controller.lastError {
                    Section("Needs attention") {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Recent controls") {
                    if controller.events.isEmpty {
                        ContentUnavailableView(
                            "No controls yet",
                            systemImage: "iphone.and.arrow.forward.inward",
                            description: Text("Finish the three steps, scan the QR code, then tap Agent 1 on your iPhone.")
                        )
                    } else {
                        ForEach(controller.events.prefix(12)) { event in
                            HStack {
                                Text(event.key)
                                    .monospaced()
                                Spacer()
                                Text(event.phase == .pressed ? "PRESSED" : "RELEASED")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(event.phase == .pressed ? .green : .secondary)
                            }
                        }
                    }
                }

                Section("Transport") {
                    Label("Codex app-server", systemImage: "terminal")
                    Text("Default mode uses Codex's local JSON-RPC interface. Accessibility and BLE hardware are not used. BLE HID remains only as an optional compatibility mode.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Vibe Watch Bridge")
            .toolbar {
                ToolbarItem {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        controller.refreshSetup()
                    }
                }
            }
            .task {
                while !Task.isCancelled {
                    controller.refreshSetup()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }
}

private struct SetupSummary: View {
    let controller: BridgeController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: controller.isReady ? "checkmark.circle.fill" : "wand.and.stars")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(controller.isReady ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.isReady ? "Ready for your iPhone" : "Let’s get you connected")
                        .font(.title3.weight(.semibold))
                    Text(controller.isReady
                         ? "Scan the QR code below. No iPhone app is needed."
                         : "Keep this Mac app open. BLE hardware and Accessibility are not required.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: Double(controller.completedSetupSteps), total: 3)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("\(controller.completedSetupSteps) of 3 steps complete")

            Text("\(controller.completedSetupSteps) of 3 ready")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct SetupStepRow: View {
    let number: Int
    let isComplete: Bool
    let title: String
    let detail: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title3)
                .foregroundStyle(isComplete ? .green : .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Text("Done")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct QRConnectPanel: View {
    let controller: BridgeController

    var body: some View {
        if let url = controller.browserURL {
            HStack(alignment: .center, spacing: 20) {
                QRCodeView(value: url.absoluteString)
                    .frame(width: 144, height: 144)
                    .opacity(controller.isReady ? 1 : 0.35)

                VStack(alignment: .leading, spacing: 9) {
                    Text(controller.isReady ? "Scan with Camera" : "QR unlocks when ready")
                        .font(.headline)
                    Text(controller.isReady
                         ? "Safari opens the controller automatically. Tap controls normally; hold only the microphone."
                         : "You can scan now, but the controller will show which Mac setup step remains.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(url.absoluteString)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 8)
        } else {
            ContentUnavailableView(
                "No local network address",
                systemImage: "wifi.exclamationmark",
                description: Text("Connect this Mac to Wi-Fi, then press Refresh.")
            )
        }
    }
}

#Preview {
    BridgeDashboard(controller: BridgeController())
        .frame(width: 580, height: 700)
}
