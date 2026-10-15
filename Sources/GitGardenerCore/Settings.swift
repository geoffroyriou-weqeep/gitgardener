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

    public static func load(from fileURL: URL = Settings.defaultFileURL) -> Settings {
        (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
    }

    public func save(to fileURL: URL = Settings.defaultFileURL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: fileURL, options: .atomic)
    }
}
