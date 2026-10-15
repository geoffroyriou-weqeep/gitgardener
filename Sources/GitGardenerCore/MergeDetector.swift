import Foundation

/// Answers "which Base Branches contain this branch".
struct MergeDetector {
    private static let defaultBaseBranches = ["main", "master", "develop"]

    private let git: Git
    /// Base Branch name to the ref compared against (`origin/<base>` when it exists).
    private let baseRefs: [(name: String, ref: String)]

    var baseBranches: [String] { baseRefs.map(\.name) }

    init(repoPath: URL, overrides: [String]?) {
        git = Git(path: repoPath)
        let git = git
        func exists(_ ref: String) -> Bool { (try? git.run("rev-parse", "--verify", "--quiet", ref)) != nil }
        baseRefs = (overrides ?? Self.defaultBaseBranches).compactMap { name in
            if exists("refs/remotes/origin/\(name)") { return (name, "origin/\(name)") }
            return exists("refs/heads/\(name)") ? (name, name) : nil
        }
    }

    func mergedInto(_ branchRef: String) -> [String] {
        baseRefs.filter { isMerged(branchRef, into: $0.ref) }.map(\.name)
    }

    private func isMerged(_ branch: String, into base: String) -> Bool {
        if (try? git.run("merge-base", "--is-ancestor", branch, base)) != nil { return true }
        return isSquashMerged(branch, into: base)
    }

    private func isSquashMerged(_ branch: String, into base: String) -> Bool {
        guard let mergeBase = try? git.run("merge-base", base, branch),
              let squash = try? git.run(
                  "-c", "user.name=GitGardener", "-c", "user.email=gitgardener@localhost",
                  "commit-tree", "\(branch)^{tree}", "-p", mergeBase, "-m", "squash"
              ),
              let cherry = try? git.run("cherry", base, squash)
        else { return false }
        let lines = cherry.split(separator: "\n")
        return lines.count == 1 && lines[0].hasPrefix("-")
    }
}
