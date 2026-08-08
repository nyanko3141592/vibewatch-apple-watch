import SwiftUI

struct RelayDashboard: View {
    @Bindable var relay: PhoneRelay

    var body: some View {
        TabView {
            PhoneControlView(relay: relay)
                .tabItem { Label("Controls", systemImage: "hand.tap") }

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
                                "No control events",
                                systemImage: "hand.tap",
                                description: Text("Press a control on this iPhone or Apple Watch.")
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
                .navigationTitle("Connection")
            }
            .tabItem { Label("Connection", systemImage: "network") }
        }
    }
}

#Preview {
    RelayDashboard(relay: PhoneRelay())
}
