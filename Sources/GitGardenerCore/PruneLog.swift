import Foundation

public struct PruneLog: Sendable {
    public static let defaultFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/GitGardener/prune-log.json")

    public struct Entry: Codable, Sendable {
        public let repoPath: String
        public let branch: String
        public let commit: String
        public let date: Date
        public let deletedOnOrigin: Bool

        public init(repoPath: String, branch: String, commit: String, date: Date = Date(), deletedOnOrigin: Bool) {
            self.repoPath = repoPath
            self.branch = branch
            self.commit = commit
            self.date = date
            self.deletedOnOrigin = deletedOnOrigin
        }
    }

    private let fileURL: URL

    public init(fileURL: URL = PruneLog.defaultFileURL) {
        self.fileURL = fileURL
    }

    public func append(_ entry: Entry) throws {
        let data = try encoder.encode(try entries() + [entry])
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func entries() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([Entry].self, from: Data(contentsOf: fileURL))
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
