import GitGardenerCore
import SwiftUI

extension Notification.Name {
    static let branchRestored = Notification.Name("GitGardener.branchRestored")
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
                    Button("Restaurer") { restore(row.entry) }.disabled(!row.isRestorable)
                }
            }
        }
        .padding()
        .frame(minWidth: 700, minHeight: 300)
        .task { reload() }
    }

    private func reload() {
        do {
            rows = try log.entries().sorted { $0.date > $1.date }.map { Row(entry: $0, isRestorable: log.isRestorable($0)) }
        } catch {
            errorMessage = "\(error)"
        }
    }

    private func restore(_ entry: PruneLog.Entry) {
        do {
            try log.restore(entry)
            errorMessage = nil
            NotificationCenter.default.post(name: .branchRestored, object: nil)
        } catch {
            errorMessage = "\(error)"
        }
        reload()
    }
}
