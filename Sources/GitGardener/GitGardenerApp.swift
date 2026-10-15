import AppKit
import GitGardenerCore
import SwiftUI

@main
struct GitGardenerApp: App {
    @State private var settings = GitGardenerCore.Settings.load()

    init() {
        // `swift run` launches a bare executable: without this it gets no window or Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("GitGardener") {
            RepoListView(settings: $settings)
                .onChange(of: settings) { _, new in try? new.save() }
        }
        Window("Journal", id: "prune-log") {
            PruneLogView()
        }
        SwiftUI.Settings {
            SettingsView(settings: $settings)
        }
    }
}
