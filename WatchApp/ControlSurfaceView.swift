import SwiftUI
import WatchKit

struct ControlSurfaceView: View {
    @Bindable var link: WatchLink
    @State private var page = 0
    @State private var selectedAgent = 0
    @State private var planEnabled = false

    var body: some View {
        TabView(selection: $page) {
            AgentSurface(
                agents: link.agents,
                selectedAgent: $selectedAgent,
                send: send
            )
            .tag(0)

            ActionSurface(planEnabled: $planEnabled, send: send)
                .tag(1)
        }
        .tabViewStyle(.verticalPage)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                LinkIndicator(state: link.state)
            }
        }
    }

    private func send(_ event: VibeEvent) {
        link.send(event)
        guard event.phase == .pressed else { return }

        let haptic: WKHapticType
        switch event.key {
        case VibeControl.ok.rawValue:
            haptic = .success
        case VibeControl.ng.rawValue:
            haptic = .failure
        default:
            haptic = .click
        }
        WKInterfaceDevice.current().play(haptic)
    }
}

private struct AgentSurface: View {
    let agents: [VibeAgentState]
    @Binding var selectedAgent: Int
    let send: (VibeEvent) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size * 0.34

            ZStack {
                Color.black.ignoresSafeArea()

                ForEach(agents) { agent in
                    let angle = Angle.degrees(-120 + Double(agent.id) * 60)
                    let x = center.x + cos(angle.radians) * radius
                    let y = center.y + sin(angle.radians) * radius

                    PressableControl { phase in
                        if phase == .pressed { selectedAgent = agent.id }
                        send(.agent(index: agent.id, phase: phase))
                    } label: { pressed in
                        AgentOrb(agent: agent, selected: selectedAgent == agent.id, pressed: pressed)
                    }
                    .frame(width: size * 0.25, height: size * 0.25)
                    .position(x: x, y: y)
                    .accessibilityLabel("Agent \(agent.id + 1)")
                }

                MicrophoneButton(send: send)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .position(center)
            }
        }
        .containerBackground(.black, for: .tabView)
    }
}

private struct AgentOrb: View {
    let agent: VibeAgentState
    let selected: Bool
    let pressed: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(agent.color.opacity(pressed ? 0.95 : agent.brightness * 0.7))
            Circle()
                .stroke(selected ? Color.purple : agent.color.opacity(0.75), lineWidth: selected ? 4 : 1.5)
            Text("\(agent.id + 1)")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(selected || pressed ? .black : .white)
        }
        .shadow(color: selected ? .purple.opacity(0.75) : .clear, radius: 7)
    }
}

private struct MicrophoneButton: View {
    let send: (VibeEvent) -> Void

    var body: some View {
        PressableControl { phase in
            send(.control(.microphonePrimary, phase: phase))
            send(.control(.microphoneSecondary, phase: phase))
        } label: { pressed in
            ZStack {
                Circle().fill(pressed ? Color.blue : Color(white: 0.1))
                Circle().stroke(.blue, lineWidth: pressed ? 4 : 2)
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("Push to talk")
        .accessibilityHint("Hold while speaking")
    }
}

private struct ActionSurface: View {
    @Binding var planEnabled: Bool
    let send: (VibeEvent) -> Void

    private let controls: [(VibeControl, String, String, Color)] = [
        (.ok, "OK", "checkmark", .blue),
        (.assistant, "AI", "sparkles", .white),
        (.plan, "PLAN", "switch.2", .cyan),
        (.fast, "FAST", "bolt.fill", .purple),
        (.ng, "NG", "xmark", .orange),
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size * 0.34

            ZStack {
                Color.black.ignoresSafeArea()

                ForEach(Array(controls.enumerated()), id: \.element.0) { index, item in
                    let angle = Angle.degrees(-90 + Double(index) * 72)
                    let x = center.x + cos(angle.radians) * radius
                    let y = center.y + sin(angle.radians) * radius

                    PressableControl { phase in
                        if item.0 == .plan, phase == .pressed { planEnabled.toggle() }
                        send(.control(item.0, phase: phase))
                    } label: { pressed in
                        ActionOrb(
                            label: item.1,
                            symbol: item.2,
                            color: item.0 == .plan && planEnabled ? .green : item.3,
                            pressed: pressed
                        )
                    }
                    .frame(width: size * 0.27, height: size * 0.27)
                    .position(x: x, y: y)
                    .accessibilityLabel(item.1)
                }

                MicrophoneButton(send: send)
                    .frame(width: size * 0.31, height: size * 0.31)
                    .position(center)
            }
        }
        .containerBackground(.black, for: .tabView)
    }
}

private struct ActionOrb: View {
    let label: String
    let symbol: String
    let color: Color
    let pressed: Bool

    var body: some View {
        ZStack {
            Circle().fill(pressed ? color.opacity(0.9) : Color(white: 0.06))
            Circle().stroke(color, lineWidth: pressed ? 4 : 2)
            VStack(spacing: 1) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(pressed && color != .white ? .black : .white)
        }
    }
}

private struct LinkIndicator: View {
    let state: WatchLink.State

    var body: some View {
        Circle()
            .fill(state == .connected ? Color.green : Color.orange)
            .frame(width: 7, height: 7)
            .accessibilityLabel("Relay \(state.rawValue)")
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

#Preview("Agents") {
    ControlSurfaceView(link: WatchLink())
}
