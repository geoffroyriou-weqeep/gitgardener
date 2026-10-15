# [GitGardener] S4 -- Prune Log view and branch restore

Blocked by: S3

Goal
Open the Prune Log, see the last 30 days of pruned branches, and restore one (locally, and on origin if it was deleted there) while its commits still exist.

Done when
`swift test --filter PruneLogTests` passes and, in the app, a branch pruned with "aussi sur origin" on a throwaway repo comes back locally and on origin after clicking "Restaurer" in the Journal window.

Context
- Read `CONTEXT.md` (Prune Log).
- Git keeps unreferenced commits for about 2 weeks by default; restore must check the commit still exists and disable the button otherwise.
- Worktrees are never restorable (uncommitted changes are gone by design); only branch entries exist in the log.

Reuse
- `PruneLog`, `PruneLog.Entry` (S3, `Sources/GitGardenerCore/PruneLog.swift`)
- `Git` (S1)
- `GitGardenerApp` (S1)
- `RepoListView` (S1/S2/S3)

Create
- `PruneLog.restore(_ entry: Entry) throws`: recreates the branch, pushes it back to origin when `deletedOnOrigin`.
- `PruneLog.isRestorable(_ entry: Entry) -> Bool`: the commit still exists and no branch with that name exists locally.
- `Sources/GitGardener/PruneLogView.swift`: "Journal" window listing entries.

Do
1. Write `Tests/GitGardenerCoreTests/PruneLogTests.swift` (RED) on temp repos (bare origin + clone) with a temp log file: after deleting a pushed branch locally and on origin and appending its entry, `restore` recreates the local branch at the logged commit and `origin/<branch>` exists again; an entry whose branch name already exists locally → `isRestorable == false`; an entry with a non-existent commit → `isRestorable == false`; an entry older than 30 days is absent from `entries()`.
2. Implement `isRestorable` (GREEN): `git cat-file -e <commit>^{commit}` succeeds and `git show-ref --verify --quiet refs/heads/<branch>` fails.
3. Implement `restore` (GREEN): `git branch <branch> <commit>`; if `deletedOnOrigin`, `git push origin <branch>`; then remove the entry from the log.
4. Make `entries()` drop entries older than 30 days and rewrite the file when it dropped any.
5. Create `PruneLogView`: newest first, columns Repo, Branche, Commit (short), Date, "aussi sur origin"; a "Restaurer" button per row, disabled when not restorable; show the error message on failure.
6. Add a `Window("Journal", id: "prune-log")` scene in `GitGardenerApp` and a "Journal" toolbar button in `RepoListView` opening it; rescan after a restore.
7. Run `swift test --filter PruneLogTests`, then check the Done when manually on a throwaway repo.

Do not
- Violate SOLID or DRY
- Add abstractions, files, or refactors not listed above
- Make the code more complex than required -- simplest working code is mandatory
- Prefer deeper modules (narrow interface, hide complexity) when it does not add complexity or abstractions beyond this plan -- simplest working code still wins
- Inline or squash a listed Create into another file just to stay under the file cap -- if Create needs a module/class file, create that file (ask before exceeding Touch limit)
- Invent naming that conflicts with repo conventions (Swift API Design Guidelines, CONTEXT.md vocabulary, English only in code, French only in UI strings)
- Implement production code before the failing focused test when TDD applies (must be RED → GREEN)
- Exceed the touch limits for this slice without asking
- Add an "Annuler" toast or undo shortcut (rejected in grill)
- Restore Worktrees
- Use the em dash character anywhere

Touch limit
- ≤6 files (excl. test), ≤2 new public symbols (`restore`, `isRestorable`), 1 focused test, single concern
- File count is a thinness guide: maintainable Create modules beat minimizing files
