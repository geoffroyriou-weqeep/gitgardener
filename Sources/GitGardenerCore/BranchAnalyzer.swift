import Foundation

public struct BranchAnalyzer: Sendable {
    public static let defaultConductorDatabaseURL: URL? = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.conductor.app/conductor.db")

    public struct Report: Sendable {
        public let verdict: SafetyVerdict
        public let mergedInto: [String]
        public let pullRequest: PullRequest?
        public let conductor: ConductorState?
    }

    public struct PullRequest: Sendable {
        public let number: Int
        public let state: String
        public let url: URL
    }

    public enum ConductorState: Sendable {
        case active, archived
    }

    private struct GitHubPullRequest: Decodable {
        let number: Int
        let headRefName: String
        let baseRefName: String
        let headRefOid: String
        let isCrossRepository: Bool
        let state: String
        let url: URL
    }

    private let baseBranchOverrides: [String: [String]]
    private let conductor: ConductorCatalog
    private let githubPath: String?

    public init(
        baseBranchOverrides: [String: [String]] = [:],
        conductorDatabaseURL: URL? = BranchAnalyzer.defaultConductorDatabaseURL,
        usesGitHub: Bool = true
    ) {
        self.baseBranchOverrides = baseBranchOverrides
        conductor = ConductorCatalog(databaseURL: conductorDatabaseURL)
        githubPath = usesGitHub ? Self.resolveGitHubPath() : nil
    }

    public func analyze(_ repo: Repo) -> [String: Report] {
        let detector = MergeDetector(repoPath: repo.path, overrides: baseBranchOverrides[repo.path.path])
        let pullRequests = githubPullRequests(for: repo)
        var reports: [String: Report] = [:]

        for branch in repo.branches {
            let worktree = repo.worktrees.first { $0.branch == branch.name }
            reports[branch.name] = report(
                name: branch.name, ref: "refs/heads/\(branch.name)", location: branch.location,
                isCheckedOutInMainFolder: branch.isCheckedOutInMainFolder,
                worktree: worktree, worktreePath: branch.worktreePath,
                repo: repo, detector: detector, pullRequests: pullRequests[branch.name] ?? []
            )
        }
        for name in repo.originOnlyBranches {
            reports[name] = report(
                name: name, ref: "refs/remotes/origin/\(name)", location: nil,
                isCheckedOutInMainFolder: false, worktree: nil, worktreePath: nil,
                repo: repo, detector: detector, pullRequests: pullRequests[name] ?? []
            )
        }
        return reports
    }

    /// The Base Branches merges are checked against: the override, or the auto-detected ones that exist.
    public func baseBranches(of repo: Repo) -> [String] {
        MergeDetector(repoPath: repo.path, overrides: baseBranchOverrides[repo.path.path]).baseBranches
    }

    /// `location` is nil for Origin Only branches.
    private func report(
        name: String, ref: String, location: Repo.BranchLocation?,
        isCheckedOutInMainFolder: Bool, worktree: Repo.Worktree?, worktreePath: URL?,
        repo: Repo, detector: MergeDetector, pullRequests: [GitHubPullRequest]
    ) -> Report {
        var mergedInto = detector.mergedInto(ref)
        // A merged PR only vouches for the exact commit it merged: a reused branch name or a fork's
        // same-named branch with newer commits must not be reported as Merged.
        let tip = try? Git(path: repo.path).run("rev-parse", "--verify", "--quiet", ref)
        for pr in pullRequests where pr.state == "MERGED" && !pr.isCrossRepository && pr.headRefOid == tip
            && detector.baseBranches.contains(pr.baseRefName) {
            if !mergedInto.contains(pr.baseRefName) { mergedInto.append(pr.baseRefName) }
        }
        let conductorState = conductor.state(repoPath: repo.path, branch: name, worktreePath: worktreePath)
        let latest = pullRequests.max { $0.number < $1.number }

        var verdict: SafetyVerdict
        if detector.protectedBranches.contains(name) || isCheckedOutInMainFolder || conductorState == .active {
            verdict = .blocked
        } else if !mergedInto.isEmpty {
            verdict = .safe
        } else if case let .tracked(ahead, _) = location, ahead == 0 {
            verdict = .review
        } else {
            verdict = .risky
        }
        if let worktree, worktree.dirtyFileCount > 0 {
            verdict = max(verdict, .risky)
        }
        return Report(
            verdict: verdict,
            mergedInto: mergedInto,
            pullRequest: latest.map { PullRequest(number: $0.number, state: $0.state, url: $0.url) },
            conductor: conductorState
        )
    }

    private func githubPullRequests(for repo: Repo) -> [String: [GitHubPullRequest]] {
        guard let githubPath,
              let output = try? Git.execute(
                  githubPath,
                  ["pr", "list", "--state", "all", "--limit", "500", "--json", "number,headRefName,headRefOid,isCrossRepository,baseRefName,state,url"],
                  currentDirectory: repo.path
              ),
              let pullRequests = try? JSONDecoder().decode([GitHubPullRequest].self, from: Data(output.utf8))
        else { return [:] }
        return Dictionary(grouping: pullRequests, by: \.headRefName)
    }

    static func resolveGitHubPath() -> String? {
        let fm = FileManager.default
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        if let path = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return path }
        // Login shells may print banners: only trust a last line that is an executable file.
        let output = try? Git.execute("/bin/zsh", ["-lc", "command -v gh"])
        let path = output?.split(separator: "\n").last.map(String.init)
        return path.flatMap { fm.isExecutableFile(atPath: $0) ? $0 : nil }
    }
}
