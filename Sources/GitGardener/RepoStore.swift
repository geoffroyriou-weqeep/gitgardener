import Foundation
import GitGardenerCore
import Observation

struct Pick: Hashable {
    let repo: URL
    let branch: String
}

/// What is known about each Repo of the list, analyzed one by one so a slow or broken Repo delays nothing else.
@MainActor @Observable
final class RepoStore {
    enum Problem: Equatable {
        case missing
        case failed(String)
    }

    struct Entry {
        var repo: Repo?
        var reports: [String: BranchAnalyzer.Report] = [:]
        var baseBranches: [String] = []
        var isLoading = false
        var problem: Problem?
    }

    private struct Loaded: Sendable {
        let repo: Repo
        let reports: [String: BranchAnalyzer.Report]
        let baseBranches: [String]
    }

    /// What an analysis reports before it is done: the Repo as soon as it is read, then each verdict as it is found.
    private enum Progress: Sendable {
        case repo(Repo)
        case report(String, BranchAnalyzer.Report)
    }

    private enum Outcome: Sendable {
        case loaded(Loaded)
        case missing
        case failed(String)
    }

    /// Enough to keep the Mac responsive: each analysis already runs many git processes.
    private static let maxConcurrentAnalyses = 4

    private(set) var entries: [URL: Entry] = [:]
    private(set) var prerequisites: [Prerequisite] = []
    private(set) var lastAnalysis: Date?
    private(set) var analyzedCount = 0
    private(set) var queuedCount = 0
    var picks: Set<Pick> = []
    /// A result is kept only if no newer analysis of the same Repo was started meanwhile.
    private var generations: [URL: Int] = [:]

    var isAnalyzing: Bool { queuedCount > analyzedCount }

    func checkPrerequisites() async {
        prerequisites = await Task.detached { Prerequisite.missing() }.value
    }

    func analyze(_ paths: [URL], baseBranchOverrides: [String: [String]]) async {
        guard !paths.isEmpty else { return }
        if !isAnalyzing {
            analyzedCount = 0
            queuedCount = 0
        }
        queuedCount += paths.count
        var started: [(URL, Int)] = []
        for path in paths {
            let generation = (generations[path] ?? 0) + 1
            generations[path] = generation
            entries[path, default: Entry()].isLoading = true
            started.append((path, generation))
        }
        let analyzer = await Task.detached { BranchAnalyzer(baseBranchOverrides: baseBranchOverrides) }.value

        await withTaskGroup(of: (URL, Int, Outcome).self) { group in
            var pending = started[...]
            func startNext() {
                guard let (path, generation) = pending.popFirst() else { return }
                group.addTask {
                    let outcome = Self.load(path, analyzer: analyzer) { progress in
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated { self.apply(progress, to: path, generation: generation) }
                        }
                    }
                    return (path, generation, outcome)
                }
            }
            for _ in 0..<Self.maxConcurrentAnalyses { startNext() }
            for await (path, generation, outcome) in group {
                apply(outcome, to: path, generation: generation)
                analyzedCount += 1
                startNext()
            }
        }
        if !isAnalyzing { lastAnalysis = Date() }
    }

    func forget(_ path: URL) {
        entries[path] = nil
        generations[path] = (generations[path] ?? 0) + 1
        picks = picks.filter { $0.repo != path }
    }

    /// Rows show up with their branch data first and get their verdict one by one.
    private func apply(_ progress: Progress, to path: URL, generation: Int) {
        guard generations[path] == generation, var entry = entries[path], entry.isLoading else { return }
        switch progress {
        case let .repo(repo): entry.repo = repo
        case let .report(name, report): entry.reports[name] = report
        }
        entries[path] = entry
    }

    private func apply(_ outcome: Outcome, to path: URL, generation: Int) {
        guard generations[path] == generation, var entry = entries[path] else { return }
        entry.isLoading = false
        switch outcome {
        case let .loaded(loaded):
            entry.repo = loaded.repo
            entry.reports = loaded.reports
            entry.baseBranches = loaded.baseBranches
            entry.problem = nil
        case .missing:
            entry = Entry(problem: .missing)
        case let .failed(message):
            entry = Entry(problem: .failed(message))
        }
        entries[path] = entry
        // Rows only appear with their verdict, so a Blocked branch is never selectable, even for a moment.
        picks = picks.filter { pick in
            pick.repo != path || entry.reports[pick.branch].map { $0.verdict != .blocked } ?? false
        }
    }

    private nonisolated static func load(
        _ path: URL, analyzer: BranchAnalyzer, onProgress: @escaping @Sendable (Progress) -> Void
    ) -> Outcome {
        guard FileManager.default.fileExists(atPath: path.path) else { return .missing }
        do {
            let repo = try RepoReader.read(at: path)
            onProgress(.repo(repo))
            let reports = analyzer.analyze(repo) { name, report in onProgress(.report(name, report)) }
            return .loaded(Loaded(repo: repo, reports: reports, baseBranches: analyzer.baseBranches(of: repo)))
        } catch {
            return .failed("\(error)")
        }
    }
}
