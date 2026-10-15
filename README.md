# GitGardener

A personal macOS app to inspect every local git repository and prune stale worktrees and branches in bulk. See [CONTEXT.md](CONTEXT.md) for the vocabulary (Repo, Worktree, Safety Verdict, Prune, ...).

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode or Command Line Tools)
- `git` on the PATH

## Build and install

```sh
./build.sh              # builds build/GitGardener.app (ad-hoc signed)
./build.sh --install    # same, then copies it to /Applications/GitGardener.app
```

`build.sh` uses the toolchain selected by `xcode-select`, or `~/Developer/CommandLineTools` when that folder exists and `DEVELOPER_DIR` is not set. The icon is drawn by `swift Scripts/make-icon.swift Resources/AppIcon.icns`.

## Development

```sh
swift build             # debug build
swift run GitGardener   # launch the app from the terminal
swift test              # run the GitGardenerCore tests
```

Layout:

- `Sources/GitGardenerCore`: reading repos, branch analysis, safety verdicts, pruning and prune log (no UI)
- `Sources/GitGardener`: SwiftUI app
- `Tests/GitGardenerCoreTests`: tests for the core module
- `docs/adr`, `docs/slices`: decisions and implementation slices

## Usage

1. **Repos**: add folders with the + button or by dropping them on the window. A repo folder is added as is, a worktree folder adds its main repo, and a folder holding several repos lets you tick the ones to add. Nothing is ever discovered on its own. Edit a repo's Base Branches from the pill in its header.
2. **Repo list**: each repo shows its worktrees and branches with their location (local only, tracked, gone, origin only) and a safety verdict (Safe, Review, Risky, Blocked).
3. **Prune**: select branches and worktrees, then confirm in the sheet, which lists what will be destroyed. Verdicts are recomputed just before deleting. Deleting the origin copy is an explicit opt-in.
4. **Prune log**: pruned branches are kept for 30 days and can be restored while their commits still exist.

Safety rules: Base Branches and branches checked out in a repo's main folder are never offered for deletion, and active Conductor workspaces are never pruned (archive them from Conductor).
