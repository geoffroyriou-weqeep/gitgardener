import Foundation

struct Git {
    struct Failure: Error, CustomStringConvertible {
        let executable: String
        let arguments: [String]
        let stderr: String
        var description: String {
            "\(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.joined(separator: " ")) failed: \(stderr)"
        }
    }

    /// Kills a command still running after this long (a hung `fetch` or `push` would otherwise block forever).
    private static let timeout: TimeInterval = 120

    let path: URL

    @discardableResult
    func run(_ arguments: [String]) throws -> String {
        // `core.fsmonitor` would let a scanned repo's config run an arbitrary program on `git status`.
        try Self.execute("/usr/bin/git", ["-C", path.path, "-c", "core.fsmonitor=false"] + arguments)
    }

    @discardableResult
    func run(_ arguments: String...) throws -> String { try run(arguments) }

    static func execute(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        // Never wait for a credential, host key or `gh` prompt nobody can answer.
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GH_PROMPT_DISABLED"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        // stderr goes to a temp file: no helper thread is needed to drain it, so callers
        // blocking on many concurrent runs cannot starve the thread pool.
        let errURL = FileManager.default.temporaryDirectory.appendingPathComponent("git-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let err = try FileHandle(forWritingTo: errURL)
        defer { try? FileManager.default.removeItem(at: errURL) }
        process.standardOutput = out
        process.standardError = err
        try process.run()
        try? err.close()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer { watchdog.cancel() }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errData = (try? Data(contentsOf: errURL)) ?? Data()
        guard process.terminationStatus == 0, process.terminationReason == .exit else {
            throw Failure(executable: executable, arguments: arguments, stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
