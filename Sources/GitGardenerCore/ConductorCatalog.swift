import Foundation

/// Conductor Workspaces read from the Conductor database (read-only).
struct ConductorCatalog {
    private struct Row: Decodable {
        let workspace_path: String?
        let branch: String?
        let state: String?
        let root_path: String?

        var isArchived: Bool { state == "archived" }
    }

    private static let query = """
        select w.workspace_path, w.branch, w.state, r.root_path \
        from workspaces w join repos r on r.id = w.repository_id
        """

    private let rows: [Row]

    init(databaseURL: URL?) {
        guard let databaseURL,
              let output = try? Git.execute("/usr/bin/sqlite3", ["-readonly", "-json", databaseURL.path, Self.query]),
              let data = output.data(using: .utf8)
        else {
            rows = []
            return
        }
        rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
    }

    func state(repoPath: URL, branch: String, worktreePath: URL?) -> BranchAnalyzer.ConductorState? {
        if let worktreePath,
           rows.contains(where: { !$0.isArchived && Self.sameFolder($0.workspace_path, worktreePath) }) {
            return .active
        }
        let isArchived = rows.contains { $0.isArchived && $0.branch == branch && Self.sameFolder($0.root_path, repoPath) }
        return isArchived ? .archived : nil
    }

    private static func sameFolder(_ path: String?, _ url: URL) -> Bool {
        guard let path else { return false }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
    }
}
