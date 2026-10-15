import AppKit
import GitGardenerCore
import SwiftUI

struct SettingsView: View {
    @Binding var settings: GitGardenerCore.Settings
    @State private var repoPaths: [URL] = []

    var body: some View {
        Form {
            Section("Dossiers à scanner") {
                urlList($settings.scanRoots, addLabel: "Ajouter un dossier…")
            }
            Section("Repos ajoutés manuellement") {
                urlList($settings.manualRepos, addLabel: "Ajouter un repo…")
            }
            Section("Repos masqués") {
                ForEach(settings.hiddenRepos, id: \.self) { url in
                    HStack {
                        Text(url.path)
                        Spacer()
                        Button("Afficher") { settings.hiddenRepos.removeAll { $0 == url } }
                    }
                }
            }
            Section("Branches de base (séparées par des virgules, vide = détection automatique)") {
                ForEach(repoPaths, id: \.self) { url in
                    TextField(url.lastPathComponent, text: baseBranches(for: url))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 560)
        .task(id: settings.scanRoots + settings.manualRepos) {
            let current = settings
            let repos = try? await Task.detached {
                try RepoScanner(scanRoots: current.scanRoots, manualRepos: current.manualRepos).scan()
            }.value
            repoPaths = (repos ?? []).map(\.path)
        }
    }

    private func urlList(_ urls: Binding<[URL]>, addLabel: String) -> some View {
        Group {
            ForEach(urls.wrappedValue, id: \.self) { url in
                HStack {
                    Text(url.path)
                    Spacer()
                    Button("Retirer") { urls.wrappedValue.removeAll { $0 == url } }
                }
            }
            Button(addLabel) {
                if let url = chooseDirectory() { urls.wrappedValue.append(url) }
            }
        }
    }

    private func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func baseBranches(for repo: URL) -> Binding<String> {
        Binding(
            get: { settings.baseBranchOverrides[repo.path]?.joined(separator: ", ") ?? "" },
            set: { text in
                let names = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                settings.baseBranchOverrides[repo.path] = names.isEmpty ? nil : names
            }
        )
    }
}
