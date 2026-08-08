import SwiftUI

@main
struct VibeWatchWatchApp: App {
    @State private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            ControlSurfaceView(link: link)
                .task { link.activate() }
        }
    }
}
