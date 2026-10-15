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
                .gardenStyle()
        }
        .defaultSize(width: 1280, height: 800)
        Window("Journal", id: "prune-log") {
            PruneLogView().gardenStyle()
        }
    }
}

private extension View {
    /// The UI is French: dates and relative times must be too, whatever the system language.
    func gardenStyle() -> some View {
        tint(.garden).environment(\.locale, Locale(identifier: "fr_FR"))
    }
}
