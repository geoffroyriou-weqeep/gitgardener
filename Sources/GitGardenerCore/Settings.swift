import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public static let defaultFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/GitGardener/settings.json")

    /// The Repos the user added, in the order they were added.
    public var repos: [URL]
    /// Base Branch names per Repo path; a missing entry means auto-detect.
    public var baseBranchOverrides: [String: [String]]

    public init(repos: [URL] = [], baseBranchOverrides: [String: [String]] = [:]) {
        self.repos = repos
        self.baseBranchOverrides = baseBranchOverrides
    }

    /// Every key is optional, so a file written by an older version (with Scan Roots) still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repos = try container.decodeIfPresent([URL].self, forKey: .repos) ?? []
        baseBranchOverrides = try container.decodeIfPresent([String: [String]].self, forKey: .baseBranchOverrides) ?? [:]
    }

    /// Defaults when the file is missing; an unreadable file is first moved aside so the next save cannot erase it.
    public static func load(from fileURL: URL = Settings.defaultFileURL) -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else { return Settings() }
        if let settings = try? JSONDecoder().decode(Settings.self, from: data) { return settings }
        let backup = fileURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        return Settings()
    }

    public func save(to fileURL: URL = Settings.defaultFileURL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: fileURL, options: .atomic)
    }

    /// Adds the Repos not already listed (the same folder reached through a symlink counts once).
    public mutating func add(_ paths: [URL]) {
        for path in paths.map(RepoLocator.canonical) where !repos.map(RepoLocator.canonical).contains(path) {
            repos.append(path)
        }
    }

    public mutating func remove(_ path: URL) {
        repos.removeAll { RepoLocator.canonical($0) == RepoLocator.canonical(path) }
        baseBranchOverrides[path.path] = nil
    }

    /// A Repo moved on disk keeps its place in the list and its Base Branches.
    public mutating func relocate(_ old: URL, to new: URL) {
        let new = RepoLocator.canonical(new)
        guard let index = repos.firstIndex(where: { RepoLocator.canonical($0) == RepoLocator.canonical(old) }) else { return }
        if repos.map(RepoLocator.canonical).contains(new) {
            remove(old)
            return
        }
        repos[index] = new
        if let overrides = baseBranchOverrides.removeValue(forKey: old.path) {
            baseBranchOverrides[new.path] = overrides
        }
    }
}
