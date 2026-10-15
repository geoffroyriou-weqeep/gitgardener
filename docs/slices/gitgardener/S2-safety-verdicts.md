# [GitGardener] S2 -- Safety Verdicts, Merged detection and Conductor badges

Blocked by: S1

Goal
Every branch and Worktree row shows its Safety Verdict, the Base Branch(es) it is Merged into, its pull request, and a Conductor badge, with filters and per-Repo counters.

Done when
`swift test --filter BranchAnalyzerTests` passes and, in the app, a weqeep branch squash-merged into `develop` shows 🟢 "Mergée dans develop", the branch of the active `porto-novo` Conductor Workspace shows ⛔ with a "Conductor actif" badge, and the sidebar shows counters like "weqeep · 🟢 41 · 🟠 12 · 🔴 3".

Context
- Read `CONTEXT.md` (Base Branch, Merged, Safety Verdict, Dirty Worktree, Conductor Workspace).
- Still read-only: no git command that writes refs on disk except the throwaway `git commit-tree` object used for squash detection (it creates an unreferenced object, no ref).
- `gh` lives at `/opt/homebrew/bin/gh` on this machine; an app launched from Finder has a minimal PATH, so resolve `gh` once via `/bin/zsh -lc 'command -v gh'` and skip GitHub data silently if not found or if the call fails.
- Conductor database: `~/Library/Application Support/com.conductor.app/conductor.db`, SQLite, opened read-only via `/usr/bin/sqlite3 -readonly`. Query: `select w.workspace_path, w.branch, w.state, r.root_path from workspaces w join repos r on r.id = w.repository_id`. `state = 'archived'` means archived; any other state is active.

Reuse
- `Repo`, `Repo.Branch`, `Repo.Worktree`, `Repo.BranchLocation` (S1, `Sources/GitGardenerCore/Repo.swift`)
- `RepoScanner` (S1)
- `Git` (S1, `Sources/GitGardenerCore/Git.swift`)
- `RepoListView` (S1)

Create
- `Sources/GitGardenerCore/SafetyVerdict.swift`: public `enum SafetyVerdict: Int, Comparable, Sendable { case safe, review, risky, blocked }` (ordering = severity, so "worst of" is `max`).
- `Sources/GitGardenerCore/BranchAnalyzer.swift`: public `struct BranchAnalyzer` with `init(baseBranchOverrides: [String: [String]] = [:], conductorDatabaseURL: URL? = BranchAnalyzer.defaultConductorDatabaseURL, usesGitHub: Bool = true)` and `func analyze(_ repo: Repo) -> [String: Report]` keyed by branch name (local and Origin Only). Nested public `Report` (`verdict: SafetyVerdict`, `mergedInto: [String]`, `pullRequest: PullRequest?`, `conductor: ConductorState?`), `PullRequest` (`number`, `state`, `url`), `ConductorState` (`active`, `archived`). `baseBranchOverrides` is keyed by Repo path.
- `Sources/GitGardenerCore/MergeDetector.swift`: internal; answers "which Base Branches contain this branch".
- `Sources/GitGardenerCore/ConductorCatalog.swift`: internal; loads Conductor Workspaces (path, branch, active/archived, Repo root path) from the database, empty when the file is missing or the query fails.

Do
1. Write `Tests/GitGardenerCoreTests/BranchAnalyzerTests.swift` (RED), building temp repos with the git CLI (bare origin + clone, `develop` and `main` pushed), with `conductorDatabaseURL: nil` and `usesGitHub: false`. Cases: a branch squash-merged into `develop` (`git merge --squash` + commit + push) → `.safe`, `mergedInto == ["develop"]`; a branch merged with a regular merge into `main` → `.safe`, `mergedInto` contains `"main"`; a pushed, unmerged, not-ahead branch → `.review`; a local-only branch with commits → `.risky`; a pushed branch ahead by 1 → `.risky`; `develop` → `.blocked`; the branch checked out in the main folder → `.blocked`; a merged branch whose Worktree has a modified file → `.risky`; an unmerged Origin Only branch → `.risky`, a merged Origin Only branch → `.safe`. Add one case with a tiny temp SQLite file (created with `sqlite3` CLI, same schema subset) marking a Worktree as an active Conductor Workspace → `.blocked`, `conductor == .active`.
2. Create `SafetyVerdict.swift`.
3. Implement `MergeDetector` (GREEN): Base Branches = `baseBranchOverrides[repo.path]` if present, else those of `main`, `master`, `develop` existing locally or on origin. For each Base Branch use `origin/<base>` if it exists, else `<base>`. A branch is Merged into a base when either:
   - `git merge-base --is-ancestor <branch> <base>` succeeds, or
   - squash check: `git commit-tree <branch>^{tree} -p $(git merge-base <base> <branch>) -m squash` produces a commit `C`, and `git cherry <base> C` outputs a single line starting with `-`.
   - Origin Only branches use `origin/<name>` as `<branch>`.
4. Implement `ConductorCatalog` (GREEN): match a Worktree by `workspace_path`; match a branch of an archived Workspace by `root_path == repo.path` and `branch`.
5. Implement `BranchAnalyzer.analyze` (GREEN), verdict rules in this order:
   - Base Branch, or `isCheckedOutInMainFolder`, or its Worktree is an active Conductor Workspace → `.blocked`
   - Merged into at least one Base Branch → `.safe`
   - Origin Only and not Merged → `.risky`
   - `.tracked(ahead: 0, _)` → `.review`
   - otherwise (`localOnly`, `gone`, ahead > 0) → `.risky`
   - if the branch has a Worktree with `dirtyFileCount > 0`, verdict = `max(verdict, .risky)` (never lowers `.blocked`)
   - GitHub (when `usesGitHub`): one call per Repo `gh pr list --state all --limit 500 --json number,headRefName,baseRefName,state,url`, run in the Repo folder; attach the latest PR per `headRefName`; a `MERGED` PR whose `baseRefName` is a Base Branch also adds that base to `mergedInto` (covers merges git cannot see).
6. Update `RepoListView`: columns Verdict (🟢 Sûre / 🟠 À vérifier / 🔴 Risquée / ⛔ Bloquée), Mergée dans, PR (`#738` + state, opens the URL), Worktree badge ("Conductor actif" / "Workspace Conductor archivé", plus "N fichiers modifiés"); a "Ouvrir dans Conductor" button on active Conductor rows (`NSWorkspace` open of bundle id `com.conductor.app`); filters above the table (verdict, Branch Location, "dernier commit il y a plus de N jours", search by name); sidebar counters per Repo and for "Tous les repos". Analysis runs off the main thread after the scan.
7. Run `swift test --filter BranchAnalyzerTests` and `swift run GitGardener`; check the Done when rows.

Do not
- Violate SOLID or DRY
- Add abstractions, files, or refactors not listed above
- Make the code more complex than required -- simplest working code is mandatory
- Prefer deeper modules (narrow interface, hide complexity) when it does not add complexity or abstractions beyond this plan -- simplest working code still wins
- Inline or squash a listed Create into another file just to stay under the file cap -- if Create needs a module/class file, create that file (ask before exceeding Touch limit)
- Invent naming that conflicts with repo conventions (Swift API Design Guidelines, CONTEXT.md vocabulary, English only in code, French only in UI strings)
- Implement production code before the failing focused test when TDD applies (must be RED → GREEN)
- Exceed the touch limits for this slice without asking
- Write to the Conductor database or call the `conductor` CLI
- Fetch, delete, or select rows for deletion (that is S3)
- Make `MergeDetector` or `ConductorCatalog` public
- Use the em dash character anywhere

Touch limit
- ≤6 files (excl. test), ≤2 new public symbols (`SafetyVerdict`, `BranchAnalyzer`; nested types do not count), 1 focused test, single concern
- File count is a thinness guide: maintainable Create modules beat minimizing files
