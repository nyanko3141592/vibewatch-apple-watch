import SwiftUI

struct PressableControl<Label: View>: View {
    let onPhaseChange: (VibeEventPhase) -> Void
    @ViewBuilder let label: (Bool) -> Label

    @State private var isPressed = false

    var body: some View {
        label(isPressed)
            .contentShape(.circle)
            .scaleEffect(isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.18, bounce: 0.35), value: isPressed)
            .simultaneousGesture(
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
            .accessibilityAddTraits(.isButton)
    }
}
