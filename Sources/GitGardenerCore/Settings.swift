import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public static let defaultFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/GitGardener/settings.json")

    public var scanRoots: [URL]
    public var manualRepos: [URL]
    public var hiddenRepos: [URL]
    /// Base Branch names per Repo path; a missing entry means auto-detect.
    public var baseBranchOverrides: [String: [String]]

    public init(
        scanRoots: [URL] = RepoScanner.defaultScanRoots,
        manualRepos: [URL] = [],
        hiddenRepos: [URL] = [],
        baseBranchOverrides: [String: [String]] = [:]
    ) {
        self.scanRoots = scanRoots
        self.manualRepos = manualRepos
        self.hiddenRepos = hiddenRepos
        self.baseBranchOverrides = baseBranchOverrides
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
}
