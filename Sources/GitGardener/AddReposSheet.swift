import SwiftUI

/// The Repos found inside the parent folders the user added, all unticked: nothing is added without a tick.
struct AddReposSheet: View {
    struct Group: Identifiable {
        let parent: URL
        let repos: [URL]
        var id: URL { parent }
    }

    let groups: [Group]
    let tracked: Set<URL>
    let onAdd: ([URL]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ticked: Set<URL> = []

    private var addable: [URL] { groups.flatMap(\.repos).filter { !tracked.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choisir les repos à suivre").font(.title2.bold())
            Text("Ces dossiers contiennent plusieurs repos. Cochez ceux à ajouter : le dossier parent n'est pas mémorisé.")
                .foregroundStyle(.secondary)
            List {
                ForEach(groups) { group in
                    Section(group.parent.abbreviatedPath) {
                        ForEach(group.repos, id: \.self) { repo in
                            row(repo, in: group.parent)
                        }
                    }
                }
            }
            .frame(minHeight: 260)
            HStack {
                Button(ticked.count == addable.count ? "Tout décocher" : "Tout cocher") {
                    ticked = ticked.count == addable.count ? [] : Set(addable)
                }
                .disabled(addable.isEmpty)
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Ajouter \(ticked.count) repo\(ticked.count > 1 ? "s" : "")") {
                    onAdd(addable.filter(ticked.contains))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(ticked.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
    }

    private func row(_ repo: URL, in parent: URL) -> some View {
        let isTracked = tracked.contains(repo)
        return Toggle(isOn: Binding(
            get: { isTracked || ticked.contains(repo) },
            set: { if $0 { ticked.insert(repo) } else { ticked.remove(repo) } }
        )) {
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(Color.garden)
                Text(repo.lastPathComponent)
                let relative = String(repo.path.dropFirst(parent.path.count + 1))
                if relative != repo.lastPathComponent {
                    Text(relative).font(.caption).foregroundStyle(.secondary)
                }
                if isTracked { Tag(text: "déjà suivi") }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isTracked)
    }
}
