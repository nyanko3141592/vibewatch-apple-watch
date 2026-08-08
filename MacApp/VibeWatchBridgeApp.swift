import SwiftUI

@main
struct VibeWatchBridgeApp: App {
    @State private var controller = BridgeController()

    var body: some Scene {
        WindowGroup {
            BridgeDashboard(controller: controller)
                .task { controller.start() }
        }
        .defaultSize(width: 480, height: 420)
    }
}
