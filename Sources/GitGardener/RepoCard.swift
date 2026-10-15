import AppKit
import GitGardenerCore
import SwiftUI

private typealias Report = BranchAnalyzer.Report

/// One Repo of the list: its header, then its branches or what went wrong reading it.
struct RepoCard: View {
    let path: URL
    let entry: RepoStore.Entry
    let filters: Filters
    @Binding var picks: Set<Pick>
    @Binding var baseBranchOverride: [String]?
    let onRetry: () -> Void
    let onLocate: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.problem == nil ? "folder.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(entry.problem == nil ? Color.garden : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(path.lastPathComponent).font(.title3.bold())
                Text(path.abbreviatedPath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if entry.isLoading { ProgressView().controlSize(.small).padding(.leading, 4) }
            Spacer()
            if let repo = entry.repo {
                BaseBranchesButton(repo: repo, effective: entry.baseBranches, override: $baseBranchOverride)
                VerdictCounts(reports: Array(entry.reports.values))
            }
            Menu {
                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([path]) }
                Button("Ouvrir dans le Terminal", action: openInTerminal)
                Divider()
                Button("Retirer de la liste", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.problem {
        case .missing:
            HStack {
                Label("Dossier introuvable : il a été déplacé ou supprimé.", systemImage: "questionmark.folder")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Localiser…", action: onLocate)
                Button("Retirer", action: onRemove)
            }
        case let .failed(message):
            HStack(alignment: .top) {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
                Spacer()
                Button("Réessayer", action: onRetry)
            }
        case nil:
            if let repo = entry.repo {
                BranchTable(repo: repo, reports: entry.reports, filters: filters, picks: $picks)
            } else {
                ProgressView("Analyse…").controlSize(.small).frame(maxWidth: .infinity)
            }
        }
    }

    private func openInTerminal() {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([path], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Rows a Repo shows once the filters are applied.
struct VisibleBranches {
    let rows: [Repo.Branch]
    let originOnly: [String]

    init(repo: Repo, reports: [String: BranchAnalyzer.Report], filters: Filters) {
        rows = repo.branches.filter { filters.matches($0, verdict: reports[$0.name]?.verdict) }
        // Origin Only branches have no location nor local commit date to filter on.
        originOnly = filters.location == nil && filters.minimumAgeInDays == 0
            ? repo.originOnlyBranches.filter { filters.matches(name: $0, verdict: reports[$0]?.verdict) }
            : []
    }

    var isEmpty: Bool { rows.isEmpty && originOnly.isEmpty }
}

private struct BranchRow: Identifiable {
    let branch: Repo.Branch
    let report: Report?
    let worktree: Repo.Worktree?
    var id: String { branch.name }
}

private struct BranchTable: View {
    let repo: Repo
    let reports: [String: Report]
    let filters: Filters
    @Binding var picks: Set<Pick>

    var body: some View {
        let visible = VisibleBranches(repo: repo, reports: reports, filters: filters)
        let rows = visible.rows.map { branch in
            BranchRow(branch: branch, report: reports[branch.name], worktree: repo.worktrees.first { $0.branch == branch.name })
        }
        if visible.isEmpty {
            Label {
                Text(filters.isActive ? "Aucune branche ne correspond aux filtres." : "Rien à tailler ici.")
            } icon: {
                Image(systemName: "leaf.fill").foregroundStyle(Color.garden)
            }
            .foregroundStyle(.secondary)
        } else {
            if !rows.isEmpty { table(rows) }
            if !visible.originOnly.isEmpty { originOnlyList(visible.originOnly) }
        }
    }

    private func table(_ rows: [BranchRow]) -> some View {
        Table(rows, selection: selection) {
            TableColumn("Verdict") { row in
                if let verdict = row.report?.verdict { VerdictTag(verdict: verdict) }
            }
            .width(min: 84, ideal: 96, max: 110)
            TableColumn("Branche") { Text($0.branch.name).fontDesign(.monospaced).help($0.branch.name) }
                .width(min: 120, ideal: 210)
            TableColumn("Emplacement") { LocationLabel(location: $0.branch.location) }
                .width(min: 80, ideal: 120)
            TableColumn("Dernier commit") {
                Text($0.branch.lastCommitDate, format: .relative(presentation: .named)).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 110)
            TableColumn("Mergée dans") {
                let merged = $0.report?.mergedInto.joined(separator: ", ") ?? ""
                Text(merged).fontDesign(.monospaced).lineLimit(1).help(merged)
            }
                .width(min: 50, ideal: 80)
            TableColumn("PR") { row in
                if let pr = row.report?.pullRequest {
                    Link(destination: pr.url) { Text("#\(pr.number) \(pr.stateLabel)").lineLimit(1).truncationMode(.tail) }
                        .help(pr.url.absoluteString)
                }
            }
            .width(min: 40, ideal: 80)
            TableColumn("Worktree") { WorktreeCell(worktree: $0.worktree, conductor: $0.report?.conductor) }
                .width(min: 80, ideal: 170)
        }
        .scrollDisabled(true)
        .frame(height: CGFloat(rows.count + 1) * 28 + 6)
    }

    private func originOnlyList(_ names: [String]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(names, id: \.self) { name in
                    Toggle(isOn: originOnlySelection(name)) {
                        HStack {
                            if let verdict = reports[name]?.verdict { VerdictTag(verdict: verdict) }
                            Text(name).fontDesign(.monospaced)
                            if let merged = reports[name]?.mergedInto, !merged.isEmpty {
                                Text("mergée dans \(merged.joined(separator: ", "))").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(reports[name]?.verdict == .blocked)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("\(names.count) uniquement sur origin", systemImage: "icloud").foregroundStyle(.secondary)
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
}

private struct WorktreeCell: View {
    let worktree: Repo.Worktree?
    let conductor: BranchAnalyzer.ConductorState?

    var body: some View {
        HStack(spacing: 4) {
            // A Conductor Workspace folder is named after a city: the badge says more than the name.
            if let conductor {
                Tag(text: conductor == .active ? "Conductor actif" : "Conductor archivé", color: .purple)
                    .help(worktree?.path.path ?? "")
            } else if let worktree {
                Label(worktree.path.lastPathComponent, systemImage: "folder").lineLimit(1).help(worktree.path.path)
            }
            if let dirty = worktree?.dirtyFileCount, dirty > 0 {
                Tag(text: "\(dirty) modifiés", symbol: "pencil", color: .orange)
            }
            if conductor == .active {
                Button("Ouvrir", action: openConductor).buttonStyle(.link).help("Ouvrir dans Conductor")
            }
        }
    }

    private func openConductor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.conductor.app") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Shows the Base Branches and edits them by ticking the Repo's real branches.
private struct BaseBranchesButton: View {
    let repo: Repo
    let effective: [String]
    @Binding var override: [String]?
    @State private var isEditing = false

    private var checked: [String] { override ?? effective }

    private var candidates: [String] {
        let names = Set(repo.branches.map(\.name) + repo.originOnlyBranches)
        return checked.filter(names.contains)
            + names.subtracting(checked).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        Button { isEditing = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text(checked.isEmpty ? "Aucune base" : checked.joined(separator: ", ")).fontDesign(.monospaced)
                if override == nil { Text("auto").foregroundStyle(.secondary) }
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Branches de base : modifier")
        .popover(isPresented: $isEditing, arrowEdge: .bottom) { editor }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Branches de base").font(.headline)
            Text("Une branche mergée dans l'une d'elles est sûre. Les branches de base ne sont jamais proposées à la suppression.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(candidates, id: \.self) { name in
                        Toggle(name, isOn: isChecked(name))
                            .toggleStyle(.checkbox)
                            .fontDesign(.monospaced)
                            // At least one Base Branch: an empty override would silently mean auto-detect.
                            .disabled(checked == [name])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            Divider()
            HStack {
                Text(override == nil ? "Détection automatique" : "Choix manuel").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Revenir à l'auto") { override = nil }.disabled(override == nil)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func isChecked(_ name: String) -> Binding<Bool> {
        Binding(
            get: { checked.contains(name) },
            set: { isOn in
                let names = isOn ? checked + [name] : checked.filter { $0 != name }
                override = candidates.filter(names.contains)
            }
        )
    }
}

private extension BranchAnalyzer.PullRequest {
    var stateLabel: String {
        switch state {
        case "MERGED": "mergée"
        case "CLOSED": "fermée"
        case "OPEN": "ouverte"
        default: state.lowercased()
        }
    }
}
