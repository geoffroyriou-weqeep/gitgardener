# Repos are added by hand, never discovered

The list of Repos is exactly the local folders the user added (button or drag and drop), because the app must not depend on one person's folder layout and must never show or analyze a repository nobody asked for. Adding a parent folder lists the Repos inside it once, all unticked, and remembers nothing about the parent; adding a Worktree folder adds its main Repo. The previous Scan Roots and Hidden Repos are dropped without migration.

## Considered Options

- **Default Scan Roots** (`~/sites`, `~/perso`, `~/code`, or a longer list of usual names): a guess that silently shows nothing for any other layout.
- **Discovery from `~`** with exclusions: layout-independent, but slow, and reading `~/Documents`, `~/Desktop` or `~/Downloads` triggers macOS privacy prompts.
- **Repos listed from GitHub via `gh`**: says nothing about where (or whether) a local clone exists, and makes `gh` mandatory.
