import SwiftUI

struct RelayDashboard: View {
    @Bindable var relay: PhoneRelay

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    LabeledContent("Apple Watch", value: relay.state.rawValue)
                    LabeledContent("Mac host", value: relay.macHost.state.rawValue)
                    if !relay.macHost.hostName.isEmpty {
                        LabeledContent("Bridge", value: relay.macHost.hostName)
                    }
                    TextField("Mac pairing code", text: $relay.macPairingCode)
                        .keyboardType(.numberPad)
                    if let error = relay.macHost.lastError {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Send preview agent state") {
                        relay.sendPreviewAgentState()
                    }
                } footer: {
                    Text("Enter the six-digit code shown by Vibe Watch Bridge on the Mac. The relay is then automatic.")
                }

                Section("Recent events") {
                    if relay.events.isEmpty {
                        ContentUnavailableView(
                            "No Watch events",
                            systemImage: "applewatch",
                            description: Text("Press a control in the Vibe Watch app.")
                        )
                    } else {
                        ForEach(relay.events) { event in
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
            .navigationTitle("Vibe Watch Relay")
        }
    }
}

#Preview {
    RelayDashboard(relay: PhoneRelay())
}
