import SwiftUI

@main
struct VibeWatchRelayApp: App {
    @State private var relay = PhoneRelay()

    var body: some Scene {
        WindowGroup {
            RelayDashboard(relay: relay)
                .task { relay.activate() }
        }
    }
}
