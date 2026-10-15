import GitGardenerCore
import SwiftUI

struct RepoListView: View {
    @State private var repos: [Repo] = []
    @State private var selection: Repo.ID?
    @State private var isScanning = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Text("Tous les repos").tag(Repo.ID?.none)
                ForEach(repos) { repo in
                    Text(repo.name).tag(Repo.ID?.some(repo.id))
                }
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                    ForEach(visibleRepos) { RepoSection(repo: $0) }
                }
                .padding()
            }
        }
        .toolbar {
            Button("Actualiser", action: rescan).disabled(isScanning)
        }
        .task { await scan() }
    }

    private var visibleRepos: [Repo] {
        selection == nil ? repos : repos.filter { $0.id == selection }
    }

    private func rescan() {
        Task { await scan() }
    }

    private func scan() async {
        isScanning = true
        defer { isScanning = false }
        do {
            repos = try await Task.detached { try RepoScanner().scan() }.value
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
    }
}

private struct RepoSection: View {
    let repo: Repo

    var body: some View {
        VStack(alignment: .leading) {
            Text(repo.name).font(.title2.bold())
            Table(repo.branches) {
                TableColumn("Branche", value: \.name)
                TableColumn("Emplacement") { Text($0.location.label) }
                TableColumn("Dernier commit") { Text($0.lastCommitDate, style: .relative) }
                TableColumn("Worktree") { Text($0.worktreePath?.path ?? "") }
            }
            .frame(height: CGFloat(repo.branches.count + 1) * 28 + 8)
            if !repo.originOnlyBranches.isEmpty {
                DisclosureGroup("Uniquement sur origin") {
                    ForEach(repo.originOnlyBranches, id: \.self) { Text($0) }
                }
            }
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
