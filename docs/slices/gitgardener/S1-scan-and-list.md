# [GitGardener] S1 -- Read-only scan and list of Repos, branches and Worktrees

Blocked by: none

Goal
Launch the app and see, for every Repo found under the default Scan Roots, its local branches, Worktrees and Origin Only branches with their Branch Location.

Done when
`swift test --filter RepoScannerTests` passes and `swift run GitGardener` opens a window listing `~/sites/weqeep` with its branches (Branch Location shown, e.g. "Local uniquement", "↑2 ↓5", "Origin supprimée") and its 3 Worktrees grouped under it.

Context
- Read `CONTEXT.md` (Repo, Scan Root, Worktree, Branch Location) before coding; use those words in type and property names.
- Build env: `DEVELOPER_DIR=$HOME/Developer/CommandLineTools` (already exported in `~/.zshrc`). No Xcode, no XCTest: tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- Architecture decision: `docs/adr/0001-native-swiftui-without-xcode.md`. Git is driven through the `git` CLI, never a git library.
- Nothing in this slice writes to any repo. Read-only commands only.

Reuse
- Nothing (first slice).

Create
- `Package.swift`: swift-tools-version 6.0, platform `.macOS(.v14)`, library target `GitGardenerCore` (Sources/GitGardenerCore), executable target `GitGardener` (Sources/GitGardener, depends on GitGardenerCore), test target `GitGardenerCoreTests` (Tests/GitGardenerCoreTests).
- `Sources/GitGardenerCore/Git.swift`: internal `struct Git` running `/usr/bin/git -C <path> <args>` via `Process`, returning trimmed stdout and throwing on non-zero exit (stderr in the error). Single choke point for every git call in the app.
- `Sources/GitGardenerCore/Repo.swift`: public `struct Repo: Identifiable, Sendable` (id = path) with `path: URL`, `name: String`, `branches: [Branch]`, `worktrees: [Worktree]`, `originOnlyBranches: [String]`; nested public `Branch` (`name`, `location: BranchLocation`, `lastCommitDate: Date`, `worktreePath: URL?`, `isCheckedOutInMainFolder: Bool`), `Worktree` (`path`, `branch: String?`, `dirtyFileCount: Int`, `lastActivity: Date`), `BranchLocation` enum (`localOnly`, `tracked(ahead: Int, behind: Int)`, `gone`).
- `Sources/GitGardenerCore/RepoScanner.swift`: public `struct RepoScanner` with `init(scanRoots: [URL] = RepoScanner.defaultScanRoots)` and `func scan() throws -> [Repo]`. `defaultScanRoots` = `~/sites`, `~/perso`, `~/code`.
- `Sources/GitGardener/GitGardenerApp.swift`: `@main` SwiftUI `App` with one `WindowGroup` showing `RepoListView`.
- `Sources/GitGardener/RepoListView.swift`: `NavigationSplitView`; sidebar = "Tous les repos" + one row per Repo; detail = `Table` of branches (columns: Branche, Emplacement, Dernier commit, Worktree) and a collapsed `DisclosureGroup` "Uniquement sur origin" per Repo listing `originOnlyBranches`. Scan runs off the main thread on appear; a "Actualiser" toolbar button rescans.

Do
1. Write `Tests/GitGardenerCoreTests/RepoScannerTests.swift` (RED). In a temp dir, build with the git CLI: a bare `origin.git`; a Repo cloned from it inside a temp Scan Root with branches `main` (pushed), `pushed-ahead` (pushed then 2 extra local commits), `local-only` (never pushed), `gone-branch` (pushed with upstream, then deleted on origin and `git fetch --prune`); a branch `remote-only` pushed to origin from a second clone and absent locally; one extra Worktree outside the Scan Root on branch `wt-branch` with one modified file. Assert `RepoScanner(scanRoots: [tempRoot]).scan()` returns exactly 1 Repo with: `pushed-ahead` = `.tracked(ahead: 2, behind: 0)`, `local-only` = `.localOnly`, `gone-branch` = `.gone`, `originOnlyBranches` == `["remote-only"]`, 1 Worktree with `dirtyFileCount == 1` and `wt-branch.worktreePath` set, `main.isCheckedOutInMainFolder == true`.
2. Create `Package.swift`, `Git.swift`, `Repo.swift`.
3. Implement `RepoScanner.scan()` (GREEN):
   - Walk each Scan Root up to depth 3; a Repo is a directory containing a `.git` **directory** (a `.git` file means a Worktree, skip it); do not descend into a found Repo; skip hidden directories and `node_modules`/`vendor`.
   - Worktrees: `git worktree list --porcelain`; the first entry is the main folder (gives `isCheckedOutInMainFolder`), others are Worktrees wherever they live on disk. Dirty count = line count of `git -C <worktree> status --porcelain`. `lastActivity` = modification date of the worktree folder.
   - Branches: `git for-each-ref --format=%(refname:short)%00%(upstream:short)%00%(upstream:track)%00%(committerdate:iso8601-strict) refs/heads`. No upstream → `localOnly`; track `[gone]` → `gone`; otherwise parse `ahead N` / `behind N` (missing = 0) → `tracked`.
   - Origin Only: `git for-each-ref --format=%(refname:short) refs/remotes/origin`, drop `origin/HEAD` and `origin`, strip the `origin/` prefix, keep names with no local branch. A Repo without an `origin` remote has none.
   - Uses only the local state (no fetch in this slice).
4. Create `GitGardenerApp.swift` and `RepoListView.swift`; display Branch Location in French ("Local uniquement", "À jour", "↑2 ↓5", "Origin supprimée").
5. Run `swift test --filter RepoScannerTests` and `swift run GitGardener`; check the window against `~/sites/weqeep`.

Do not
- Violate SOLID or DRY
- Add abstractions, files, or refactors not listed above
- Make the code more complex than required -- simplest working code is mandatory
- Prefer deeper modules (narrow interface, hide complexity) when it does not add complexity or abstractions beyond this plan -- simplest working code still wins
- Inline or squash a listed Create into another file just to stay under the file cap -- if Create needs a module/class file, create that file (ask before exceeding Touch limit)
- Invent naming that conflicts with repo conventions (Swift API Design Guidelines, CONTEXT.md vocabulary, English only in code, French only in UI strings)
- Implement production code before the failing focused test when TDD applies (must be RED → GREEN)
- Exceed the touch limits for this slice without asking
- Run any git command that writes (no fetch, no delete, no checkout)
- Compute merge status or Safety Verdict (that is S2)
- Use the em dash character anywhere

Touch limit
- ≤6 files (excl. test), ≤2 new public symbols (`Repo`, `RepoScanner`; nested types inside them do not count), 1 focused test, single concern
- File count is a thinness guide: maintainable Create modules beat minimizing files
