# GitGardener

A personal macOS app to inspect every local git repository and prune stale worktrees and branches in bulk.

## Language

**Repo**:
A main git repository on disk (with a `.git` directory), found by scanning a Scan Root or added manually.
_Avoid_: Project, workspace

**Scan Root**:
A folder searched for Repos (default: `~/sites`, `~/perso`, `~/code`).

**Hidden Repo**:
A Repo found by scanning that the user chose not to display.

**Worktree**:
An additional working directory attached to a Repo, wherever it lives on disk (e.g. a Conductor workspace). Always shown under its Repo, never as a Repo itself.
_Avoid_: Workspace, checkout

**Dirty Worktree**:
A Worktree with uncommitted or untracked changes. Pruning it is Risky.

**Conductor Workspace**:
A Worktree managed by the Conductor app. Active ones are never pruned by GitGardener (they are archived from Conductor); branches of archived ones are flagged as such.

**Base Branch**:
A long-lived branch of a Repo that work is merged into (auto-detected among `main`, `master`, `develop`, editable per Repo). Never offered for deletion.
_Avoid_: Trunk, target branch

**Branch Location**:
Where a branch exists: Local Only (never pushed), Tracked (local and on origin, with ahead/behind counts), Gone (pushed, then deleted on origin), or Origin Only (on origin, not on this machine).
_Avoid_: Remote status, sync state

**Merged**:
A branch whose work is contained in at least one Base Branch, including via squash or rebase merge. Always reported with the Base Branch(es) it landed in.

**Safety Verdict**:
How much is lost by deleting a branch. Safe (Merged), Review (not Merged, every commit on origin), Risky (not Merged, has commits existing nowhere else), Blocked (Base Branch, or checked out in the Repo's main folder). A Worktree and its branch share one verdict, the worst of the two. Deleting the origin copy of a Review branch makes it Risky.
_Avoid_: Status, health

**Prune**:
Deleting selected branches and Worktrees. Pruning a Worktree removes its folder then its branch, unless the branch is kept. Local by default; deleting the origin copy is an explicit opt-in per Prune (and the only option for Origin Only branches).
_Avoid_: Clean, purge

**Prune Log**:
The record of pruned branches (Repo, branch, last commit, date, whether origin was deleted), kept 30 days, from which a branch can be restored while its commits still exist.
_Avoid_: History, trash
