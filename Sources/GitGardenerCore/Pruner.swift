import Foundation

public struct Pruner: Sendable {
    public struct Target: Identifiable, Sendable {
        public var id: String { "\(repoPath.path)#\(branch ?? worktreePath?.path ?? "")" }
        public let repoPath: URL
        public let branch: String?
        public let worktreePath: URL?
        public var keepsBranch: Bool
        public let isOriginOnly: Bool
        /// The verdict the user saw; `Plan` carries the fresh one.
        public var verdict: SafetyVerdict

        public init(
            repoPath: URL, branch: String?, worktreePath: URL?,
            keepsBranch: Bool, isOriginOnly: Bool, verdict: SafetyVerdict
        ) {
            self.repoPath = repoPath
            self.branch = branch
            self.worktreePath = worktreePath
            self.keepsBranch = keepsBranch
            self.isOriginOnly = isOriginOnly
            self.verdict = verdict
        }
    }

    public struct Plan: Sendable {
        public struct Item: Sendable {
            public let target: Target
            public let verdict: SafetyVerdict
        }

        public let items: [Item]
        public let changedVerdicts: [Item]
        public let alsoOnOrigin: Bool
        public var requiresTypedConfirmation: Bool { items.contains { $0.verdict == .risky } }
    }

    public struct Outcome: Sendable {
        public let target: Target
        public let errorMessage: String?
    }

    private let analyzer: BranchAnalyzer
    private let log: PruneLog

    public init(analyzer: BranchAnalyzer, log: PruneLog) {
        self.analyzer = analyzer
        self.log = log
    }

    public func prepare(_ targets: [Target], alsoOnOrigin: Bool) async throws -> Plan {
        var reports: [URL: [String: BranchAnalyzer.Report]] = [:]
        for path in Set(targets.map(\.repoPath)) {
            let git = Git(path: path)
            if try git.run("remote").split(separator: "\n").contains("origin") {
                _ = try git.run("fetch", "--prune", "origin")
            }
            if let repo = try RepoScanner(scanRoots: [path]).scan().first {
                reports[path] = analyzer.analyze(repo)
            }
        }

        var items: [Plan.Item] = []
        for target in targets {
            var verdict = target.branch.flatMap { reports[target.repoPath]?[$0]?.verdict } ?? target.verdict
            if verdict == .blocked { continue }
            if verdict == .review, alsoOnOrigin || target.isOriginOnly { verdict = .risky }
            items.append(Plan.Item(target: target, verdict: verdict))
        }
        return Plan(
            items: items,
            changedVerdicts: items.filter { $0.verdict != $0.target.verdict },
            alsoOnOrigin: alsoOnOrigin
        )
    }

    public func execute(_ plan: Plan) async -> [Outcome] {
        plan.items.map { item in
            Outcome(target: item.target, errorMessage: prune(item.target, alsoOnOrigin: plan.alsoOnOrigin))
        }
    }

    /// Returns an error message, or nil on success.
    private func prune(_ target: Target, alsoOnOrigin: Bool) -> String? {
        let git = Git(path: target.repoPath)
        let deletesLocalBranch = !target.keepsBranch && !target.isOriginOnly
        let deletesOnOrigin = alsoOnOrigin || target.isOriginOnly
        var deletedBranch = false
        var deletedOnOrigin = false
        var commit: String?
        var failure: String?

        do {
            if let branch = target.branch {
                commit = try git.run("rev-parse", target.isOriginOnly ? "refs/remotes/origin/\(branch)" : "refs/heads/\(branch)")
            }
            if let worktree = target.worktreePath {
                let isDirty = try !Git(path: worktree).run("status", "--porcelain").isEmpty
                try git.run(["worktree", "remove"] + (isDirty ? ["--force"] : []) + [worktree.path])
            }
            if let branch = target.branch {
                if deletesLocalBranch {
                    try git.run("branch", "-D", branch)
                    deletedBranch = true
                }
                if deletesOnOrigin {
                    try git.run("push", "origin", "--delete", branch)
                    deletedOnOrigin = true
                }
            }
        } catch {
            failure = "\(error)"
        }

        if let branch = target.branch, let commit, deletedBranch || deletedOnOrigin {
            do {
                try log.append(PruneLog.Entry(
                    repoPath: target.repoPath.path, branch: branch, commit: commit, deletedOnOrigin: deletedOnOrigin
                ))
            } catch {
                failure = failure ?? "Prune Log: \(error)"
            }
        }
        return failure
    }
}
