# [GitGardener] S5 -- Settings (Scan Roots, manual and Hidden Repos, Base Branches) and installable app

Blocked by: S2 (uses `BranchAnalyzer` overrides); can run in parallel with S3/S4 but both touch `RepoListView`, so run it after them to avoid conflicts.

Goal
Edit Scan Roots, add a Repo manually, hide or unhide a Repo, override Base Branches per Repo, all persisted; and install `GitGardener.app` in `/Applications`.

Done when
`swift test --filter SettingsTests` passes, `./build.sh --install` produces `/Applications/GitGardener.app` that launches from Finder and lists Repos with verdicts (gh found despite the Finder PATH), and hiding `old123go` from the sidebar survives an app restart.

Context
- Read `CONTEXT.md` (Scan Root, Hidden Repo, Base Branch).
- Settings file: `~/Library/Application Support/GitGardener/settings.json` (same folder as the Prune Log).
- Build env: `DEVELOPER_DIR=$HOME/Developer/CommandLineTools`; `build.sh` must export it itself when unset, since it may run from a shell without the profile.

Reuse
- `RepoScanner` (S1)
- `BranchAnalyzer` (`baseBranchOverrides`, S2)
- `GitGardenerApp`, `RepoListView` (S1 to S4)

Create
- `Sources/GitGardenerCore/Settings.swift`: public `struct Settings: Codable, Equatable` (`scanRoots: [URL]`, `manualRepos: [URL]`, `hiddenRepos: [URL]`, `baseBranchOverrides: [String: [String]]`) with `static func load(from: URL = Settings.defaultFileURL) -> Settings` (defaults when missing or unreadable: `RepoScanner.defaultScanRoots`, empty lists) and `func save(to: URL = Settings.defaultFileURL) throws`.
- `RepoScanner.init(scanRoots:manualRepos:hiddenRepos:)`: extends the S1 init with `manualRepos` and `hiddenRepos` (both default `[]`).
- `Sources/GitGardener/SettingsView.swift`: the Settings window.
- `build.sh`: builds and bundles the app.

Do
1. Write `Tests/GitGardenerCoreTests/SettingsTests.swift` (RED): `Settings` saved to a temp file and loaded back is equal; `load` on a missing file returns the defaults; `RepoScanner(scanRoots: [tempRoot], manualRepos: [repoOutsideRoot], hiddenRepos: [hiddenRepoInsideRoot]).scan()` returns the manual Repo and not the hidden one (temp repos via `git init`).
2. Implement `Settings` (GREEN).
3. Extend `RepoScanner` (GREEN): scanned Repos plus `manualRepos` that are valid Repos, minus `hiddenRepos`, deduplicated by path.
4. Wire into the app: `GitGardenerApp` loads `Settings` at launch and owns it; `RepoScanner` and `BranchAnalyzer(baseBranchOverrides:)` are built from it; any change saves and rescans. Sidebar context menu on a Repo: "Masquer".
5. Create `SettingsView` as a `Settings` scene (⌘,): Scan Roots list (add via `NSOpenPanel` directories only, remove); manual Repos (add via `NSOpenPanel`, remove); Hidden Repos (unhide); Base Branches per Repo (comma-separated text field, empty = auto-detect).
6. Create `build.sh`: `export DEVELOPER_DIR` if unset; `swift build -c release`; assemble `build/GitGardener.app/Contents/MacOS/GitGardener` and `Contents/Info.plist` (`CFBundleIdentifier` `com.geoffroyriou.gitgardener`, `CFBundleName` `GitGardener`, `CFBundleExecutable` `GitGardener`, `CFBundlePackageType` `APPL`, `LSMinimumSystemVersion` `14.0`, `CFBundleShortVersionString` `0.1.0`); ad-hoc sign with `codesign --force --sign - `; with `--install`, replace `/Applications/GitGardener.app`.
7. Run `swift test --filter SettingsTests`, then `./build.sh --install`, launch from Finder, check the Done when.

Do not
- Violate SOLID or DRY
- Add abstractions, files, or refactors not listed above
- Make the code more complex than required -- simplest working code is mandatory
- Prefer deeper modules (narrow interface, hide complexity) when it does not add complexity or abstractions beyond this plan -- simplest working code still wins
- Inline or squash a listed Create into another file just to stay under the file cap -- if Create needs a module/class file, create that file (ask before exceeding Touch limit)
- Invent naming that conflicts with repo conventions (Swift API Design Guidelines, CONTEXT.md vocabulary, English only in code, French only in UI strings)
- Implement production code before the failing focused test when TDD applies (must be RED → GREEN)
- Exceed the touch limits for this slice without asking
- Add a menu bar item, a CLI command, launch at login, or periodic refresh (rejected in grill)
- Add an app icon, notarization or auto-update
- Use the em dash character anywhere

Touch limit
- ≤6 files (excl. test): `Settings.swift`, `RepoScanner.swift`, `SettingsView.swift`, `GitGardenerApp.swift`, `RepoListView.swift`, `build.sh`; ≤2 new public symbols (`Settings`, extended `RepoScanner.init`), 1 focused test, single concern
- File count is a thinness guide: maintainable Create modules beat minimizing files
