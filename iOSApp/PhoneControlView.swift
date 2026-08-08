import SwiftUI
import UIKit

struct PhoneControlView: View {
    @Bindable var relay: PhoneRelay
    @State private var selectedAgent = 0
    @State private var planEnabled = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    connectionStatus
                    agentControls
                    actionControls
                    microphoneControl
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Vibe Watch")
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(relay.macHost.state == .connected ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            Text(relay.macHost.state == .connected ? "Connected to Mac" : "Searching for Mac")
                .font(.subheadline.weight(.medium))
            Spacer()
            if !relay.macHost.hostName.isEmpty {
                Text(relay.macHost.hostName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var agentControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AGENTS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(relay.agents) { agent in
                    PhonePressableControl { phase in
                        if phase == .pressed { selectedAgent = agent.id }
                        send(.agent(index: agent.id, phase: phase))
                    } label: { pressed in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(agent.color.opacity(pressed ? 1 : max(0.25, agent.brightness)))
                                .overlay {
                                    Circle().stroke(
                                        selectedAgent == agent.id ? Color.purple : agent.color.opacity(0.7),
                                        lineWidth: selectedAgent == agent.id ? 4 : 1
                                    )
                                }
                                .frame(width: 58, height: 58)
                                .shadow(
                                    color: selectedAgent == agent.id ? .purple.opacity(0.45) : .clear,
                                    radius: 8
                                )
                            Text("Agent \(agent.id + 1)")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.background, in: .rect(cornerRadius: 16))
                        .scaleEffect(pressed ? 0.96 : 1)
                    }
                    .accessibilityLabel("Agent \(agent.id + 1)")
                }
            }
        }
    }

    private var actionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CODEX ACTIONS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 12) {
                action(.fast, title: "FAST", symbol: "bolt.fill", color: .purple)
                action(.ok, title: "APPROVE", symbol: "checkmark.circle.fill", color: .blue)
                action(.ng, title: "REJECT", symbol: "xmark.circle.fill", color: .orange)
                action(
                    .plan,
                    title: "PLAN",
                    symbol: "switch.2",
                    color: planEnabled ? .green : .cyan
                )
                action(.assistant, title: "SEND", symbol: "arrow.up.circle.fill", color: .indigo)
            }
        }
    }

    private func action(
        _ control: VibeControl,
        title: String,
        symbol: String,
        color: Color
    ) -> some View {
        PhonePressableControl { phase in
            if control == .plan, phase == .pressed { planEnabled.toggle() }
            send(.control(control, phase: phase))
        } label: { pressed in
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2)
                Text(title)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(pressed ? .white : color)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(pressed ? color : Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.65), lineWidth: 1.5)
            }
            .clipShape(.rect(cornerRadius: 16))
            .scaleEffect(pressed ? 0.96 : 1)
        }
        .accessibilityLabel(title)
    }

    private var microphoneControl: some View {
        PhonePressableControl { phase in
            send(.control(.microphonePrimary, phase: phase))
            send(.control(.microphoneSecondary, phase: phase))
        } label: { pressed in
            Label(pressed ? "Listening… release to stop" : "Hold to talk", systemImage: "mic.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(pressed ? Color.red : Color.blue, in: .rect(cornerRadius: 18))
                .scaleEffect(pressed ? 0.98 : 1)
        }
        .accessibilityLabel("Push to talk")
        .accessibilityHint("Hold while speaking")
    }

    private func send(_ event: VibeEvent) {
        relay.sendFromPhone(event)
        guard event.phase == .pressed else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

private struct PhonePressableControl<Label: View>: View {
    let onPhaseChange: (VibeEventPhase) -> Void
    @ViewBuilder let label: (Bool) -> Label
    @State private var isPressed = false

    var body: some View {
        label(isPressed)
            .contentShape(Rectangle())
            .animation(.snappy(duration: 0.15), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        onPhaseChange(.pressed)
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        onPhaseChange(.released)
                    }
            )
    }
}

private extension VibeAgentState {
    var color: Color {
        Color(
            red: Double((colorHex >> 16) & 0xFF) / 255,
            green: Double((colorHex >> 8) & 0xFF) / 255,
            blue: Double(colorHex & 0xFF) / 255
        )
    }
}

#Preview {
    PhoneControlView(relay: PhoneRelay())
}
