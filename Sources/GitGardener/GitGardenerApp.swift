import AppKit
import SwiftUI

@main
struct GitGardenerApp: App {
    init() {
        // `swift run` launches a bare executable: without this it gets no window or Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("GitGardener") {
            RepoListView()
        }
    }
}
