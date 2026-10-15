import AppKit
import GitGardenerCore
import SwiftUI

private typealias Report = BranchAnalyzer.Report

private struct Pick: Hashable {
    let repo: Repo.ID
    let branch: String
}

private struct Filters {
    enum Location: CaseIterable {
        case localOnly, tracked, gone

        var label: String {
            switch self {
            case .localOnly: "Local uniquement"
            case .tracked: "Suivie"
            case .gone: "Origin supprimée"
            }
        }

        func matches(_ location: Repo.BranchLocation) -> Bool {
            switch (self, location) {
            case (.localOnly, .localOnly), (.gone, .gone), (.tracked, .tracked): true
            default: false
            }
        }
    }

    var verdict: SafetyVerdict?
    var location: Location?
    var minimumAgeInDays = 0
    var search = ""

    func matches(name: String, verdict reportVerdict: SafetyVerdict?) -> Bool {
        (verdict == nil || verdict == reportVerdict)
            && (search.isEmpty || name.localizedCaseInsensitiveContains(search))
    }

    func matches(_ branch: Repo.Branch, verdict: SafetyVerdict?) -> Bool {
        matches(name: branch.name, verdict: verdict)
            && (location?.matches(branch.location) ?? true)
            && branch.lastCommitDate < Date().addingTimeInterval(-Double(minimumAgeInDays) * 86_400)
    }
}

struct RepoListView: View {
    @Binding var settings: GitGardenerCore.Settings
    @State private var repos: [Repo] = []
    @State private var reports: [Repo.ID: [String: Report]] = [:]
    @State private var selection: Repo.ID?
    @State private var isScanning = false
    @State private var errorMessage: String?
    @State private var filters = Filters()
    @State private var picks: Set<Pick> = []
    @State private var isPruning = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Text(counters(name: "Tous les repos", reports: reports.values.flatMap(\.values))).tag(Repo.ID?.none)
                ForEach(repos) { repo in
                    Text(counters(name: repo.name, reports: Array((reports[repo.id] ?? [:]).values))).tag(Repo.ID?.some(repo.id))
                        .contextMenu { Button("Masquer") { settings.hiddenRepos.append(repo.path) } }
                }
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    FilterBar(filters: $filters)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                    ForEach(visibleRepos) { RepoSection(repo: $0, reports: reports[$0.id] ?? [:], filters: filters, picks: $picks) }
                }
                .padding()
            }
        }
        .toolbar {
            Button("Sélectionner toutes les sûres", action: selectSafe)
            Button("Journal") { openWindow(id: "prune-log") }
            Button("Actualiser") { rescan() }.disabled(isScanning)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(picks.count) sélectionnées")
                Button("Supprimer…") { isPruning = true }.disabled(picks.isEmpty)
            }
            .padding(8)
        }
        .sheet(isPresented: $isPruning) {
            PruneConfirmationSheet(targets: pruneTargets, baseBranchOverrides: settings.baseBranchOverrides, onFinish: finishPrune)
        }
        .task(id: settings) {
            // Typing a Base Branch override changes the settings on every keystroke: scan once typing pauses.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await scan()
        }
        .onReceive(NotificationCenter.default.publisher(for: .branchRestored)) { _ in rescan() }
    }

    private var visibleRepos: [Repo] {
        selection == nil ? repos : repos.filter { $0.id == selection }
    }

    private var pruneTargets: [Pruner.Target] {
        picks.sorted { ($0.repo.path, $0.branch) < ($1.repo.path, $1.branch) }.compactMap { pick in
            guard let repo = repos.first(where: { $0.id == pick.repo }),
                  let verdict = reports[pick.repo]?[pick.branch]?.verdict
            else { return nil }
            // Origin Only must come from the scan, never from a local branch that merely went missing.
            let branch = repo.branches.first { $0.name == pick.branch }
            let isOriginOnly = branch == nil && repo.originOnlyBranches.contains(pick.branch)
            guard branch != nil || isOriginOnly else { return nil }
            return Pruner.Target(
                repoPath: repo.path, branch: pick.branch, worktreePath: branch?.worktreePath,
                keepsBranch: false, isOriginOnly: isOriginOnly, verdict: verdict
            )
        }
    }

    /// Visible local branches only: Origin Only ones would be deleted on origin, which must stay an explicit choice,
    /// and rows hidden by the filters must not be pruned unseen.
    private func selectSafe() {
        for repo in visibleRepos {
            for branch in repo.branches where reports[repo.id]?[branch.name]?.verdict == .safe
                && filters.matches(branch, verdict: .safe) {
                picks.insert(Pick(repo: repo.id, branch: branch.name))
            }
        }
    }

    private func finishPrune(_ outcomes: [Pruner.Outcome]) {
        picks = []
        NotificationCenter.default.post(name: .branchesPruned, object: nil)
        let failures = outcomes.compactMap { outcome in
            outcome.errorMessage.map { "\(outcome.target.name) : \($0)" }
        }
        rescan(keeping: failures.isEmpty ? nil : failures.joined(separator: "\n"))
    }

    private func counters(name: String, reports: [Report]) -> String {
        let counts = [SafetyVerdict.safe, .review, .risky].map { verdict in
            "\(verdict.emoji) \(reports.filter { $0.verdict == verdict }.count)"
        }
        return ([name] + counts).joined(separator: " · ")
    }

    private func rescan(keeping failures: String? = nil) {
        Task {
            await scan()
            if let failures { errorMessage = failures }
        }
    }

    private func scan() async {
        isScanning = true
        defer { isScanning = false }
        do {
            let current = settings
            let scanned = try await Task.detached {
                try RepoScanner(scanRoots: current.scanRoots, manualRepos: current.manualRepos, hiddenRepos: current.hiddenRepos).scan()
            }.value
            let analyzed = await Task.detached {
                let analyzer = BranchAnalyzer(baseBranchOverrides: current.baseBranchOverrides)
                return Dictionary(uniqueKeysWithValues: scanned.map { ($0.id, analyzer.analyze($0)) })
            }.value
            // Rows only appear with their verdict, so a Blocked branch is never selectable, even for a moment.
            repos = scanned
            reports = analyzed
            errorMessage = nil
            picks = picks.filter { pick in
                analyzed[pick.repo]?[pick.branch].map { $0.verdict != .blocked } ?? false
            }
        } catch {
            errorMessage = "\(error)"
        }
    }
}

private struct FilterBar: View {
    @Binding var filters: Filters

    var body: some View {
        HStack {
            Picker("Verdict", selection: $filters.verdict) {
                Text("Tous").tag(SafetyVerdict?.none)
                ForEach([SafetyVerdict.safe, .review, .risky, .blocked], id: \.self) {
                    Text($0.label).tag(SafetyVerdict?.some($0))
                }
            }
            Picker("Emplacement", selection: $filters.location) {
                Text("Tous").tag(Filters.Location?.none)
                ForEach(Filters.Location.allCases, id: \.self) {
                    Text($0.label).tag(Filters.Location?.some($0))
                }
            }
            Stepper("Dernier commit il y a plus de \(filters.minimumAgeInDays) jours", value: $filters.minimumAgeInDays, in: 0...3650, step: 10)
            TextField("Rechercher", text: $filters.search)
        }
    }
}

private struct BranchRow: Identifiable {
    let branch: Repo.Branch
    let report: Report?
    let worktree: Repo.Worktree?
    var id: String { branch.name }
}

private struct RepoSection: View {
    let repo: Repo
    let reports: [String: Report]
    let filters: Filters
    @Binding var picks: Set<Pick>

    private var rows: [BranchRow] {
        repo.branches
            .filter { filters.matches($0, verdict: reports[$0.name]?.verdict) }
            .map { branch in
                BranchRow(
                    branch: branch,
                    report: reports[branch.name],
                    worktree: repo.worktrees.first { $0.branch == branch.name }
                )
            }
    }

    private var originOnlyBranches: [String] {
        guard filters.location == nil, filters.minimumAgeInDays == 0 else { return [] }
        return repo.originOnlyBranches.filter { filters.matches(name: $0, verdict: reports[$0]?.verdict) }
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading) {
            Text(repo.name).font(.title2.bold())
            Table(rows, selection: selection) {
                TableColumn("Verdict") { Text($0.report?.verdict.label ?? "") }
                TableColumn("Branche", value: \.branch.name)
                TableColumn("Emplacement") { Text($0.branch.location.label) }
                TableColumn("Dernier commit") { Text($0.branch.lastCommitDate, style: .relative) }
                TableColumn("Mergée dans") { Text($0.report?.mergedInto.joined(separator: ", ") ?? "") }
                TableColumn("PR") { row in
                    if let pr = row.report?.pullRequest {
                        Link("#\(pr.number) \(pr.state)", destination: pr.url)
                    }
                }
                TableColumn("Worktree") { WorktreeCell(worktree: $0.worktree, conductor: $0.report?.conductor) }
            }
            .frame(height: CGFloat(rows.count + 1) * 28 + 8)
            if !originOnlyBranches.isEmpty {
                DisclosureGroup("Uniquement sur origin") {
                    ForEach(originOnlyBranches, id: \.self) { name in
                        Toggle(
                            "\(reports[name]?.verdict.emoji ?? "") \(name) \(mergedLabel(reports[name]))",
                            isOn: originOnlySelection(name)
                        )
                        .disabled(reports[name]?.verdict == .blocked)
                    }
                }
            }
        }
    }

    /// Blocked rows can never be selected.
    private var selection: Binding<Set<String>> {
        Binding(
            get: { Set(picks.filter { $0.repo == repo.id }.map(\.branch)) },
            set: { names in
                picks = picks.filter { $0.repo != repo.id }
                    .union(names.filter { reports[$0]?.verdict != .blocked }.map { Pick(repo: repo.id, branch: $0) })
            }
        )
    }

    private func originOnlySelection(_ name: String) -> Binding<Bool> {
        Binding(
            get: { picks.contains(Pick(repo: repo.id, branch: name)) },
            set: { isOn in
                if isOn { picks.insert(Pick(repo: repo.id, branch: name)) } else { picks.remove(Pick(repo: repo.id, branch: name)) }
            }
        )
    }

    private func mergedLabel(_ report: Report?) -> String {
        guard let merged = report?.mergedInto, !merged.isEmpty else { return "" }
        return "(mergée dans \(merged.joined(separator: ", ")))"
    }
}

private struct WorktreeCell: View {
    let worktree: Repo.Worktree?
    let conductor: BranchAnalyzer.ConductorState?

    var body: some View {
        HStack {
            if let worktree {
                Text(worktree.path.lastPathComponent).help(worktree.path.path)
            }
            if let conductor {
                Text(conductor == .active ? "Conductor actif" : "Workspace Conductor archivé")
            }
            if let dirty = worktree?.dirtyFileCount, dirty > 0 {
                Text("\(dirty) fichiers modifiés")
            }
            if conductor == .active {
                Button("Ouvrir dans Conductor", action: openConductor)
            }
        }
    }

    private func openConductor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.conductor.app") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

extension SafetyVerdict {
    var emoji: String {
        switch self {
        case .safe: "🟢"
        case .review: "🟠"
        case .risky: "🔴"
        case .blocked: "⛔"
        }
    }

    var label: String {
        switch self {
        case .safe: "\(emoji) Sûre"
        case .review: "\(emoji) À vérifier"
        case .risky: "\(emoji) Risquée"
        case .blocked: "\(emoji) Bloquée"
        }
    }
}

private extension Repo.BranchLocation {
    var label: String {
        switch self {
        case .localOnly: "Local uniquement"
        case .gone: "Origin supprimée"
        case .tracked(0, 0): "À jour"
        case let .tracked(ahead, behind): "↑\(ahead) ↓\(behind)"
        }
    }
}
