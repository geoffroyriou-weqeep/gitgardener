# Native SwiftUI app built without Xcode

GitGardener is a native macOS app in SwiftUI (Swift Package Manager, macOS 14+), built and bundled into `GitGardener.app` by a shell script using only the Command Line Tools, because a native look and footprint was preferred over a web stack. Git is driven by invoking the `git` and `gh` CLIs, not a git library, so behaviour matches what the user sees in the terminal.

## Considered Options

- **Electron + React**: nothing to install and the easiest bulk-selection table, rejected for its non-native feel.
- **Tauri + React**: light, but requires installing Rust and splitting code across Rust and TypeScript.
