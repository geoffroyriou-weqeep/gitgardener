import Foundation
import Testing
@testable import GitGardenerCore

@Suite struct SettingsTests {
    private func makeTempDirectory() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("gg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp.resolvingSymlinksInPath()
    }

    @Test func saveThenLoadRoundTrips() throws {
        let tmp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("nested/settings.json")
        let settings = Settings(repos: [tmp.appendingPathComponent("a")], baseBranchOverrides: ["/x": ["main", "develop"]])
        try settings.save(to: file)
        #expect(Settings.load(from: file) == settings)
    }

    @Test func loadOfMissingFileStartsWithNoRepos() throws {
        let tmp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let settings = Settings.load(from: tmp.appendingPathComponent("missing.json"))
        #expect(settings.repos.isEmpty && settings.baseBranchOverrides.isEmpty)
    }

    @Test func fileWithScanRootsLoadsWithNoReposAndKeepsBaseBranches() throws {
        let tmp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("settings.json")
        try """
        {"scanRoots": ["file:///Users/x/code/"], "manualRepos": [], "hiddenRepos": [], "baseBranchOverrides": {"/x": ["develop"]}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let settings = Settings.load(from: file)

        #expect(settings == Settings(repos: [], baseBranchOverrides: ["/x": ["develop"]]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.path) == ["settings.json"])
    }

    @Test func addSkipsReposAlreadyListedThroughASymlink() throws {
        let tmp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let repo = tmp.appendingPathComponent("repo")
        let link = tmp.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo)
        var settings = Settings()

        settings.add([repo, link, repo])

        #expect(settings.repos == [repo])
    }

    @Test func relocateKeepsPlaceAndBaseBranches() {
        let old = URL(fileURLWithPath: "/tmp/gg-old")
        let new = URL(fileURLWithPath: "/tmp/gg-new")
        let other = URL(fileURLWithPath: "/tmp/gg-other")
        var settings = Settings(repos: [old, other], baseBranchOverrides: [old.path: ["develop"]])

        settings.relocate(old, to: new)

        #expect(settings.repos.map(\.path) == [RepoLocator.canonical(new).path, other.path])
        #expect(settings.baseBranchOverrides == [RepoLocator.canonical(new).path: ["develop"]])
    }

    @Test func removeForgetsBaseBranches() {
        let repo = URL(fileURLWithPath: "/tmp/gg-repo")
        var settings = Settings(repos: [repo], baseBranchOverrides: [repo.path: ["develop"]])

        settings.remove(repo)

        #expect(settings == Settings())
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
