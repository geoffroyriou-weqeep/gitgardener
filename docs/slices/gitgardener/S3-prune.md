# [GitGardener] S3 -- Bulk Prune with fresh verdicts and confirmation

Blocked by: S2

Goal
Select branches, Worktrees and Origin Only branches, confirm, and Prune them locally (and on origin when opted in), each Prune being recorded in the Prune Log.

Done when
`swift test --filter PrunerTests` passes and, in the app, "Sélectionner toutes les sûres" then "Supprimer…" on a throwaway repo removes those branches locally only, leaves them on origin, and writes one Prune Log entry per branch with its last commit.

Context
- Read `CONTEXT.md` (Prune, Prune Log, Safety Verdict, Dirty Worktree, Conductor Workspace).
- Grill decisions to respect: local by default; "Supprimer aussi sur origin" is an unchecked checkbox in the confirmation; Origin Only branches can only be deleted on origin; a Review branch becomes Risky when origin is also deleted; a fresh `git fetch --prune` and re-analysis of the affected Repos happens right before deletion, and the confirmation shows any verdict that changed; Blocked rows can never be selected or pruned; if the plan contains any Risky row the user must type "supprimer".
- Test only on temp repos. Never run `PrunerTests` or manual checks against `~/sites/*`.

Reuse
- `Git` (S1)
- `RepoScanner`, `Repo` (S1)
- `BranchAnalyzer`, `SafetyVerdict` (S2)
- `RepoListView` (S1/S2)

Create
- `Sources/GitGardenerCore/Pruner.swift`: public `struct Pruner` with `init(analyzer: BranchAnalyzer, log: PruneLog)`, `func prepare(_ targets: [Target], alsoOnOrigin: Bool) async throws -> Plan` and `func execute(_ plan: Plan) async -> [Outcome]`. Nested public `Target` (`repoPath`, `branch: String?`, `worktreePath: URL?`, `keepsBranch: Bool`, `isOriginOnly: Bool`), `Plan` (targets with their fresh `SafetyVerdict`, `changedVerdicts`, `alsoOnOrigin`, `requiresTypedConfirmation`), `Outcome` (target + success or error message).
- `Sources/GitGardenerCore/PruneLog.swift`: public `struct PruneLog` with `init(fileURL: URL = PruneLog.defaultFileURL)` (`~/Library/Application Support/GitGardener/prune-log.json`), `func append(_ entry: Entry) throws`, `func entries() throws -> [Entry]`. Nested public `Entry: Codable` (`repoPath`, `branch`, `commit`, `date`, `deletedOnOrigin`).
- `Sources/GitGardener/PruneConfirmationSheet.swift`: the confirmation sheet.

Do
1. Write `Tests/GitGardenerCoreTests/PrunerTests.swift` (RED) on temp repos (bare origin + clone) with a temp `PruneLog` file and `BranchAnalyzer(conductorDatabaseURL: nil, usesGitHub: false)`. Cases: pruning a Merged branch locally → local ref gone, `origin/<branch>` still exists, one log entry with the branch's former commit and `deletedOnOrigin == false`; same with `alsoOnOrigin: true` → gone on origin, `deletedOnOrigin == true`; a Review branch with `alsoOnOrigin: true` → `prepare` returns it as `.risky` and `requiresTypedConfirmation == true`; a Dirty Worktree target → folder removed and its branch deleted; same with `keepsBranch: true` → folder removed, branch kept; a Blocked target → excluded from the plan and untouched; an Origin Only target → deleted on origin.
2. Create `PruneLog.swift` (append to a JSON array file, creating the folder if needed).
3. Implement `Pruner.prepare` (GREEN): for each affected Repo run `git fetch --prune origin` (skip Repos without origin), rescan with `RepoScanner`, re-analyze with `BranchAnalyzer`; drop `.blocked` targets; if `alsoOnOrigin` (or `isOriginOnly`) turn `.review` into `.risky`; `changedVerdicts` = targets whose fresh verdict differs from the one passed by the UI; `requiresTypedConfirmation` = any `.risky`.
4. Implement `Pruner.execute` (GREEN), per target, never aborting the batch on one failure:
   - record `git rev-parse <branch>` (or `origin/<branch>` for Origin Only) before deleting
   - Worktree: `git worktree remove [--force when dirty] <path>`
   - local branch (unless `keepsBranch` or Origin Only): `git branch -D <branch>` (force, because squash merges are invisible to `-d`)
   - origin (when `alsoOnOrigin` or Origin Only): `git push origin --delete <branch>`
   - append one `PruneLog.Entry` per deleted branch
5. Update `RepoListView`: multi-selection on the table (Blocked rows not selectable); "Sélectionner toutes les sûres" button (current Repo, or all Repos on "Tous les repos"); bottom bar "N sélectionnées · Supprimer…" opening the sheet; rescan after execution and show failed Outcomes.
6. Create `PruneConfirmationSheet`: calls `prepare`, then lists Risky rows in a separate red section, shows changed verdicts, has the unchecked "Supprimer aussi sur origin" checkbox (toggling it re-runs `prepare`), a "Garder la branche" toggle on Worktree rows, and a text field that must equal "supprimer" when `requiresTypedConfirmation`; "Supprimer" calls `execute`.
7. Run `swift test --filter PrunerTests`, then check the Done when manually on a throwaway repo under a temp Scan Root.

Do not
- Violate SOLID or DRY
- Add abstractions, files, or refactors not listed above
- Make the code more complex than required -- simplest working code is mandatory
- Prefer deeper modules (narrow interface, hide complexity) when it does not add complexity or abstractions beyond this plan -- simplest working code still wins
- Inline or squash a listed Create into another file just to stay under the file cap -- if Create needs a module/class file, create that file (ask before exceeding Touch limit)
- Invent naming that conflicts with repo conventions (Swift API Design Guidelines, CONTEXT.md vocabulary, English only in code, French only in UI strings)
- Implement production code before the failing focused test when TDD applies (must be RED → GREEN)
- Exceed the touch limits for this slice without asking
- Prune anything flagged `.blocked`, including active Conductor Workspaces
- Run the Conductor archive script or touch Conductor data
- Add restore, log viewing or purge (that is S4)
- Test against real repos under `~/sites`, `~/perso`, `~/code`
- Use the em dash character anywhere

Touch limit
- ≤6 files (excl. test), ≤2 new public symbols (`Pruner`, `PruneLog`; nested types do not count), 1 focused test, single concern
- File count is a thinness guide: maintainable Create modules beat minimizing files
