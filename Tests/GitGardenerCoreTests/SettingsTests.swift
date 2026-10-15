import Foundation
import Testing
@testable import GitGardenerCore

@Suite struct SettingsTests {
    private func makeTempDirectory() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("gg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp.resolvingSymlinksInPath()
    }

    private func initRepo(at path: URL) throws {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        let git = Git(path: path)
        try git.run("init", "-b", "main")
        try git.run("-c", "user.name=T", "-c", "user.email=t@t", "commit", "--allow-empty", "-m", "init")
    }

    @Test func saveThenLoadRoundTrips() throws {
        let tmp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("nested/settings.json")
        let settings = Settings(
            scanRoots: [tmp.appendingPathComponent("a")],
            manualRepos: [tmp.appendingPathComponent("b")],
            hiddenRepos: [tmp.appendingPathComponent("c")],
            baseBranchOverrides: ["/x": ["main", "develop"]]
        )
        try settings.save(to: file)
        #expect(Settings.load(from: file) == settings)
    }

    @Test func loadOfMissingFileReturnsDefaults() throws {
        let tmp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = Settings.load(from: tmp.appendingPathComponent("missing.json"))
        #expect(settings.scanRoots == RepoScanner.defaultScanRoots)
        #expect(settings.manualRepos.isEmpty && settings.hiddenRepos.isEmpty && settings.baseBranchOverrides.isEmpty)
    }

    @Test func scanAddsManualAndDropsHiddenRepos() throws {
        let tmp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = tmp.appendingPathComponent("root")
        let kept = root.appendingPathComponent("kept")
        let hidden = root.appendingPathComponent("hidden")
        let manual = tmp.appendingPathComponent("manual")
        try [kept, hidden, manual].forEach(initRepo)

        let repos = try RepoScanner(scanRoots: [root], manualRepos: [manual, kept], hiddenRepos: [hidden]).scan()
        #expect(Set(repos.map { $0.name }) == ["kept", "manual"])
        #expect(repos.count == 2)
    }

    @Test func corruptFileIsKeptAsideNotOverwritten() throws {
        let tmp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("settings.json")
        try "{ broken".write(to: file, atomically: true, encoding: .utf8)

        let settings = Settings.load(from: file)
        try settings.save(to: file)

        let backups = try FileManager.default.contentsOfDirectory(atPath: tmp.path).filter { $0.contains("corrupt") }
        #expect(backups.count == 1)
        #expect(try String(contentsOf: tmp.appendingPathComponent(backups[0]), encoding: .utf8) == "{ broken")
    }
}
