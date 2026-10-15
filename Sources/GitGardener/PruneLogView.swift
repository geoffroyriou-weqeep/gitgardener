import GitGardenerCore
import SwiftUI

extension Notification.Name {
    static let branchRestored = Notification.Name("GitGardener.branchRestored")
    static let branchesPruned = Notification.Name("GitGardener.branchesPruned")
}

struct PruneLogView: View {
    private struct Row: Identifiable {
        let entry: PruneLog.Entry
        let isRestorable: Bool
        var id: String { "\(entry.repoPath)|\(entry.branch)|\(entry.date.timeIntervalSince1970)" }
    }

    private let log = PruneLog()
    @State private var rows: [Row] = []
    @State private var errorMessage: String?
    @State private var pendingRestore: PruneLog.Entry?
    @State private var isRestoring = false

    var body: some View {
        VStack(alignment: .leading) {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Table(rows) {
                TableColumn("Repo") { Text(URL(fileURLWithPath: $0.entry.repoPath).lastPathComponent) }
                TableColumn("Branche", value: \.entry.branch)
                TableColumn("Commit") { Text($0.entry.commit.prefix(7)).monospaced() }
                TableColumn("Date") { Text($0.entry.date, style: .date) }
                TableColumn("Aussi sur origin") { Text($0.entry.deletedOnOrigin ? "Oui" : "Non") }
                TableColumn("") { row in
                    Button("Restaurer") { pendingRestore = row.entry }.disabled(!row.isRestorable || isRestoring)
                }
            }
        }
        .padding()
        .frame(minWidth: 700, minHeight: 300)
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .branchesPruned)) { _ in Task { await reload() } }
        .confirmationDialog(
            "Restaurer \(pendingRestore?.branch ?? "") ?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { entry in
            Button(entry.deletedOnOrigin ? "Restaurer et repousser sur origin" : "Restaurer") {
                Task { await restore(entry) }
            }
        } message: { entry in
            Text(entry.deletedOnOrigin
                ? "La branche sera recréée au commit \(entry.commit.prefix(7)) et repoussée sur origin."
                : "La branche sera recréée localement au commit \(entry.commit.prefix(7)).")
        }
    }

    private func reload() async {
        let log = log
        do {
            rows = try await Task.detached {
                try log.entries().sorted { $0.date > $1.date }.map { Row(entry: $0, isRestorable: log.isRestorable($0)) }
            }.value
        } catch {
            errorMessage = "\(error)"
        }
    }

    private func restore(_ entry: PruneLog.Entry) async {
        isRestoring = true
        defer { isRestoring = false }
        let log = log
        do {
            try await Task.detached { try log.restore(entry) }.value
            errorMessage = nil
            NotificationCenter.default.post(name: .branchRestored, object: nil)
        } catch {
            errorMessage = "\(error)"
        }
        await reload()
    }
}
