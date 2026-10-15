import Foundation
import Testing
@testable import GitGardenerCore

@Suite struct BranchAnalyzerTests {
    @discardableResult
    private func git(_ args: String..., in dir: URL) throws -> String {
        try Git(path: dir).run(["-c", "user.name=T", "-c", "user.email=t@t"] + args)
    }

    private func commit(_ file: String, in dir: URL) throws {
        try file.write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        try git("add", file, in: dir)
        try git("commit", "-m", file, in: dir)
    }

    private struct Fixture {
        let repo: Repo
        let worktree: URL
        let tmp: URL
    }

    private func makeFixture() throws -> Fixture {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("gg-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let base = tmp.resolvingSymlinksInPath()
        let root = base.appendingPathComponent("root")
        let origin = base.appendingPathComponent("origin.git")
        let repo = root.appendingPathComponent("proj")
        let other = base.appendingPathComponent("other")
        let worktree = base.appendingPathComponent("wt")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: origin, withIntermediateDirectories: true)
        try git("init", "--bare", "-b", "main", in: origin)
        try git("clone", origin.path, repo.path, in: base)

        try git("checkout", "-b", "main", in: repo)
        try commit("base.txt", in: repo)
        try git("push", "-u", "origin", "main", in: repo)
        try git("checkout", "-b", "develop", in: repo)
        try git("push", "-u", "origin", "develop", in: repo)

        // Squash-merged into develop.
        try git("checkout", "-b", "squashed", in: repo)
        try commit("s.txt", in: repo)
        try git("push", "-u", "origin", "squashed", in: repo)
        try git("checkout", "develop", in: repo)
        try git("merge", "--squash", "squashed", in: repo)
        try git("commit", "-m", "squash", in: repo)
        try git("push", "origin", "develop", in: repo)

        // Regular merge into main.
        try git("checkout", "-b", "merged-main", "main", in: repo)
        try commit("m.txt", in: repo)
        try git("push", "-u", "origin", "merged-main", in: repo)
        try git("checkout", "main", in: repo)
        try git("merge", "--no-ff", "-m", "merge", "merged-main", in: repo)
        try git("push", "origin", "main", in: repo)

        // Pushed, unmerged, not ahead.
        try git("checkout", "-b", "reviewed", "main", in: repo)
        try commit("r.txt", in: repo)
        try git("push", "-u", "origin", "reviewed", in: repo)

        // Pushed and ahead by one.
        try git("checkout", "-b", "pushed-ahead", "main", in: repo)
        try commit("p1.txt", in: repo)
        try git("push", "-u", "origin", "pushed-ahead", in: repo)
        try commit("p2.txt", in: repo)

        // Local only with commits.
        try git("checkout", "-b", "local-only", "main", in: repo)
        try commit("l.txt", in: repo)

        // Merged branch with a dirty Worktree.
        try git("branch", "dirty-merged", "main", in: repo)
        try git("worktree", "add", worktree.path, "dirty-merged", in: repo)
        try "x".write(to: worktree.appendingPathComponent("dirty.txt"), atomically: true, encoding: .utf8)

        // Origin Only branches.
        try git("push", "origin", "main:refs/heads/remote-merged", in: repo)
        try git("clone", origin.path, other.path, in: base)
        try git("checkout", "-b", "remote-unmerged", in: other)
        try commit("ru.txt", in: other)
        try git("push", "origin", "remote-unmerged", in: other)
        try git("fetch", in: repo)

        try git("checkout", "-b", "main-folder", "main", in: repo)
        try commit("mf.txt", in: repo)

        return Fixture(repo: try RepoReader.read(at: repo), worktree: worktree, tmp: tmp)
    }

    @Test func classifiesBranchesWithSafetyVerdicts() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tmp) }

        let reports = BranchAnalyzer(conductorDatabaseURL: nil, usesGitHub: false).analyze(fixture.repo)

        #expect(reports["squashed"]?.verdict == .safe)
        #expect(reports["squashed"]?.mergedInto == ["develop"])
        #expect(reports["merged-main"]?.verdict == .safe)
        #expect(reports["merged-main"]?.mergedInto.contains("main") == true)
        #expect(reports["reviewed"]?.verdict == .review)
        #expect(reports["local-only"]?.verdict == .risky)
        #expect(reports["pushed-ahead"]?.verdict == .risky)
        #expect(reports["develop"]?.verdict == .blocked)
        #expect(reports["main-folder"]?.verdict == .blocked)
        #expect(reports["dirty-merged"]?.verdict == .risky)
        #expect(reports["remote-unmerged"]?.verdict == .risky)
        #expect(reports["remote-merged"]?.verdict == .safe)
    }

    @Test func blocksActiveConductorWorkspace() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tmp) }
        let database = fixture.tmp.appendingPathComponent("conductor.db")
        let sql = """
        create table repos (id integer primary key, root_path text);
        create table workspaces (workspace_path text, branch text, state text, repository_id integer);
        insert into repos values (1, '\(fixture.repo.path.path)');
        insert into workspaces values ('\(fixture.worktree.path)', 'dirty-merged', 'ready', 1);
        """
        _ = try Git.execute("/usr/bin/sqlite3", [database.path, sql])

        let reports = BranchAnalyzer(conductorDatabaseURL: database, usesGitHub: false).analyze(fixture.repo)

        #expect(reports["dirty-merged"]?.verdict == .blocked)
        #expect(reports["dirty-merged"]?.conductor == .active)
    }

    @Test func blocksWorktreesWhenConductorDatabaseIsUnreadable() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tmp) }
        let database = fixture.tmp.appendingPathComponent("conductor.db")
        try "not a database".write(to: database, atomically: true, encoding: .utf8)

        let reports = BranchAnalyzer(conductorDatabaseURL: database, usesGitHub: false).analyze(fixture.repo)

        #expect(reports["dirty-merged"]?.verdict == .blocked)
        #expect(reports["merged-main"]?.verdict == .safe)
    }

    @Test func blocksOriginDefaultBranchOutsideTheDefaults() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tmp) }
        try git("push", "origin", "main:refs/heads/trunk", in: fixture.repo.path)
        try git("branch", "trunk", "main", in: fixture.repo.path)
        try git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk", in: fixture.repo.path)
        let repo = try RepoReader.read(at: fixture.repo.path)

        let reports = BranchAnalyzer(conductorDatabaseURL: nil, usesGitHub: false).analyze(repo)

        #expect(reports["trunk"]?.verdict == .blocked)
    }

    @Test func overridesNeverExposeAutoDetectedBaseBranches() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.tmp) }

        let reports = BranchAnalyzer(
            baseBranchOverrides: [fixture.repo.path.path: ["develop"]], conductorDatabaseURL: nil, usesGitHub: false
        ).analyze(fixture.repo)

        #expect(reports["main"]?.verdict == .blocked)
        #expect(reports["develop"]?.verdict == .blocked)
        #expect(reports["merged-main"]?.mergedInto == [])
    }
}
