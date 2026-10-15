import AppKit
import GitGardenerCore
import SwiftUI

struct Filters {
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

    static let ages = [0, 30, 90, 180, 365]

    /// nil shows every branch that can be pruned: Blocked ones only appear when asked for.
    var verdict: SafetyVerdict?
    var location: Location?
    var minimumAgeInDays = 0
    var search = ""

    var isActive: Bool { verdict != nil || location != nil || minimumAgeInDays > 0 || !search.isEmpty }

    func matches(name: String, verdict reportVerdict: SafetyVerdict?) -> Bool {
        (verdict == nil ? reportVerdict != .blocked : verdict == reportVerdict)
            && (search.isEmpty || name.localizedCaseInsensitiveContains(search))
    }

    func matches(_ branch: Repo.Branch, verdict: SafetyVerdict?) -> Bool {
        matches(name: branch.name, verdict: verdict)
            && (location?.matches(branch.location) ?? true)
            && branch.lastCommitDate < Date().addingTimeInterval(-Double(minimumAgeInDays) * 86_400)
    }
}

private enum SidebarItem: Hashable {
    case all
    case repo(URL)
}

private struct Notice: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}

struct RepoListView: View {
    @Binding var settings: GitGardenerCore.Settings
    @State private var store = RepoStore()
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var filters = Filters()
    @State private var isPruning = false
    @State private var parentGroups: [AddReposSheet.Group] = []
    @State private var notices: [Notice] = []
    @State private var isDropTargeted = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 960, minHeight: 540)
        .toolbar { toolbar }
        .searchable(text: $filters.search, placement: .toolbar, prompt: "Rechercher une branche")
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay { if isDropTargeted { dropOverlay } }
        .sheet(isPresented: $isPruning) {
            PruneConfirmationSheet(targets: pruneTargets, baseBranchOverrides: settings.baseBranchOverrides, onFinish: finishPrune)
        }
        .sheet(isPresented: Binding(get: { !parentGroups.isEmpty }, set: { if !$0 { parentGroups = [] } })) {
            AddReposSheet(groups: parentGroups, tracked: Set(settings.repos)) { track($0) }
        }
        .task {
            await store.checkPrerequisites()
        }
        .task {
            await store.analyze(settings.repos, baseBranchOverrides: settings.baseBranchOverrides)
        }
        .onReceive(NotificationCenter.default.publisher(for: .branchRestored)) { _ in analyze(settings.repos) }
    }

    // MARK: Sidebar

    private var sortedRepos: [URL] {
        settings.repos.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            HStack {
                Label("Tous les repos", systemImage: "square.stack.3d.up.fill")
                Spacer()
                VerdictCounts(reports: store.entries.values.flatMap(\.reports.values))
            }
            .tag(SidebarItem.all)
            Section("Repos") {
                ForEach(sortedRepos, id: \.self) { path in
                    SidebarRow(path: path, entry: store.entries[path])
                        .tag(SidebarItem.repo(path))
                        .contextMenu {
                            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([path]) }
                            Divider()
                            Button("Retirer de la liste", role: .destructive) { remove(path) }
                        }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                AnalysisStatus(store: store, hasRepos: !settings.repos.isEmpty)
                    .padding(.horizontal, 12)
                Button(action: chooseFolders) {
                    Label("Ajouter un dossier…", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if settings.repos.isEmpty {
            ContentUnavailableView {
                Label("Aucun repo suivi", systemImage: "leaf.fill")
            } description: {
                Text("Ajoutez le dossier d'un repo, d'un worktree, ou un dossier qui en contient plusieurs. Vous pouvez aussi le glisser ici.")
            } actions: {
                Button("Ajouter un dossier…", action: chooseFolders).buttonStyle(.borderedProminent)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    banners
                    let paths = visibleRepos
                    if paths.isEmpty {
                        ContentUnavailableView.search(text: filters.search).padding(.top, 40)
                    }
                    ForEach(paths, id: \.self) { path in
                        repoCard(path)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                if !store.picks.isEmpty { actionBar }
            }
        }
    }

    private func repoCard(_ path: URL) -> some View {
        RepoCard(
            path: path,
            entry: store.entries[path] ?? RepoStore.Entry(isLoading: true),
            filters: filters,
            picks: $store.picks,
            baseBranchOverride: Binding(
                get: { settings.baseBranchOverrides[path.path] },
                set: { names in
                    settings.baseBranchOverrides[path.path] = names
                    analyze([path])
                }
            ),
            onRetry: { analyze([path]) },
            onLocate: { locate(path) },
            onRemove: { remove(path) }
        )
    }

    @ViewBuilder
    private var banners: some View {
        ForEach(store.prerequisites, id: \.self) { prerequisite in
            Banner(text: prerequisite.message, isError: prerequisite == .gitMissing)
        }
        ForEach(notices) { notice in
            Banner(text: notice.text, isError: notice.isError) { notices.removeAll { $0.id == notice.id } }
        }
    }

    /// With filters on, Repos with nothing to show are left out; Repos that failed always stay visible.
    private var visibleRepos: [URL] {
        let paths = selection.map { [$0] } ?? sortedRepos
        guard filters.isActive else { return paths }
        return paths.filter { path in
            guard let entry = store.entries[path], let repo = entry.repo, entry.problem == nil else { return true }
            return !VisibleBranches(repo: repo, reports: entry.reports, filters: filters).isEmpty
        }
    }

    private var actionBar: some View {
        let worktrees = pruneTargets.filter { $0.worktreePath != nil }.count
        return HStack(spacing: 12) {
            Image(systemName: "scissors").foregroundStyle(Color.garden)
            Text("\(store.picks.count) branche\(store.picks.count > 1 ? "s" : "") sélectionnée\(store.picks.count > 1 ? "s" : "")")
                .font(.headline)
            if worktrees > 0 {
                Text("dont \(worktrees) avec worktree").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Tout désélectionner") { store.picks = [] }
            Button(role: .destructive) { isPruning = true } label: {
                Label("Supprimer…", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.garden, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            .background(Color.garden.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                Label("Déposer pour ajouter", systemImage: "plus.circle.fill").font(.title2.bold()).foregroundStyle(Color.garden)
            }
            .padding(8)
            .allowsHitTesting(false)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Verdict", selection: $filters.verdict) {
                Text("À tailler").tag(SafetyVerdict?.none)
                ForEach([SafetyVerdict.safe, .review, .risky, .blocked], id: \.self) {
                    Text($0.pluralLabel).tag(SafetyVerdict?.some($0))
                }
            }
            .pickerStyle(.segmented)
            .help("Filtrer par verdict")
        }
        ToolbarItemGroup {
            Menu {
                Picker("Emplacement", selection: $filters.location) {
                    Text("Tous").tag(Filters.Location?.none)
                    ForEach(Filters.Location.allCases, id: \.self) {
                        Text($0.label).tag(Filters.Location?.some($0))
                    }
                }
                .pickerStyle(.inline)
                Picker("Dernier commit", selection: $filters.minimumAgeInDays) {
                    ForEach(Filters.ages, id: \.self) { days in
                        Text(days == 0 ? "Peu importe" : "Il y a plus de \(days) jours").tag(days)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                let isFiltered = filters.location != nil || filters.minimumAgeInDays > 0
                Label("Filtres", systemImage: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .help("Filtrer par emplacement et par âge")
            Button(action: selectSafe) {
                Label("Sélectionner les sûres", systemImage: "checkmark.circle")
            }
            .help("Sélectionner toutes les branches sûres affichées")
            Button { openWindow(id: "prune-log") } label: {
                Label("Journal", systemImage: "clock.arrow.circlepath")
            }
            .help("Journal des suppressions")
            Button { analyze(settings.repos) } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .help("Actualiser")
            .disabled(store.isAnalyzing)
        }
    }

    // MARK: Actions

    /// The Repo shown alone, or nil for all of them.
    private var selection: URL? {
        get { if case let .repo(path) = sidebarSelection { path } else { nil } }
        nonmutating set { sidebarSelection = newValue.map(SidebarItem.repo) ?? .all }
    }

    private func analyze(_ paths: [URL]) {
        Task { await store.analyze(paths, baseBranchOverrides: settings.baseBranchOverrides) }
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Ajouter"
        panel.message = "Choisissez un repo, un worktree, ou un dossier qui contient des repos."
        if panel.runModal() == .OK { add(panel.urls) }
    }

    private func add(_ folders: [URL]) {
        Task {
            let located = await Task.detached { folders.map { ($0, RepoLocator.locate($0)) } }.value
            var direct: [URL] = []
            var groups: [AddReposSheet.Group] = []
            for (folder, location) in located {
                switch location {
                case let .repo(repo):
                    direct.append(repo)
                case let .worktree(repo):
                    direct.append(repo)
                    notify("\(folder.lastPathComponent) est un worktree : son repo principal \(repo.lastPathComponent) a été ajouté.")
                case let .parent(repos):
                    groups.append(AddReposSheet.Group(parent: RepoLocator.canonical(folder), repos: repos))
                case .notGit:
                    notify("\(folder.lastPathComponent) n'est pas un repo git et n'en contient aucun.", isError: true)
                }
            }
            for repo in direct where settings.repos.contains(repo) {
                notify("\(repo.lastPathComponent) est déjà suivi.")
            }
            track(direct)
            parentGroups = groups
        }
    }

    private func track(_ repos: [URL]) {
        let before = Set(settings.repos)
        settings.add(repos)
        let added = settings.repos.filter { !before.contains($0) }
        if added.count == 1 { selection = added[0] }
        analyze(added)
    }

    private func remove(_ path: URL) {
        settings.remove(path)
        store.forget(path)
        if selection == path { selection = nil }
    }

    private func locate(_ path: URL) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Localiser"
        panel.message = "Où se trouve maintenant \(path.lastPathComponent) ?"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        switch RepoLocator.locate(folder) {
        case let .repo(repo), let .worktree(repo):
            settings.relocate(path, to: repo)
            store.forget(path)
            if selection == path { selection = repo }
            analyze([repo])
        case .parent, .notGit:
            notify("\(folder.lastPathComponent) n'est pas un repo git.", isError: true)
        }
    }

    private func notify(_ text: String, isError: Bool = false) {
        let notice = Notice(text: text, isError: isError)
        notices.append(notice)
        guard !isError else { return }
        Task {
            try? await Task.sleep(for: .seconds(6))
            notices.removeAll { $0.id == notice.id }
        }
    }

    private var pruneTargets: [Pruner.Target] {
        store.picks.sorted { ($0.repo.path, $0.branch) < ($1.repo.path, $1.branch) }.compactMap { pick in
            guard let entry = store.entries[pick.repo], let repo = entry.repo,
                  let verdict = entry.reports[pick.branch]?.verdict
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
        for path in visibleRepos {
            guard let entry = store.entries[path], let repo = entry.repo else { continue }
            for branch in repo.branches where entry.reports[branch.name]?.verdict == .safe
                && filters.matches(branch, verdict: .safe) {
                store.picks.insert(Pick(repo: path, branch: branch.name))
            }
        }
    }

    private func finishPrune(_ outcomes: [Pruner.Outcome]) {
        store.picks = []
        NotificationCenter.default.post(name: .branchesPruned, object: nil)
        for outcome in outcomes {
            if let message = outcome.errorMessage { notify("\(outcome.target.name) : \(message)", isError: true) }
        }
        analyze(Array(Set(outcomes.map(\.target.repoPath))))
    }
}

private struct SidebarRow: View {
    let path: URL
    let entry: RepoStore.Entry?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry?.problem == nil ? "folder.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(entry?.problem == nil ? Color.garden : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(path.lastPathComponent).lineLimit(1)
                Text(path.deletingLastPathComponent().abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if entry?.isLoading ?? true {
                ProgressView().controlSize(.mini)
            } else if let entry {
                VerdictCounts(reports: Array(entry.reports.values))
            }
        }
        .help(path.path)
    }
}

private struct AnalysisStatus: View {
    let store: RepoStore
    let hasRepos: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 6) {
                if store.isAnalyzing {
                    ProgressView().controlSize(.mini)
                    Text("Analyse \(store.analyzedCount)/\(store.queuedCount)…")
                } else if let last = store.lastAnalysis {
                    Image(systemName: "checkmark.circle").foregroundStyle(Color.garden)
                    Text("Analysé \(last, format: .relative(presentation: .named))")
                } else if !hasRepos {
                    Text("Aucun repo suivi")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct Banner: View {
    let text: String
    let isError: Bool
    var onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: isError ? "exclamationmark.octagon.fill" : "info.circle.fill")
                .foregroundStyle(isError ? .red : .blue)
            Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background((isError ? Color.red : Color.blue).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension Prerequisite {
    var message: String {
        switch self {
        case .gitMissing: "git est introuvable : installez les Command Line Tools avec « xcode-select --install », puis relancez GitGardener."
        case .githubMissing: "gh (GitHub CLI) n'est pas installé : les pull requests ne sont pas affichées."
        case .githubSignedOut: "gh n'est pas connecté (« gh auth login ») : les pull requests ne sont pas affichées."
        }
    }
}
