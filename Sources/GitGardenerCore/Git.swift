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

    let path: URL

    func run(_ arguments: [String]) throws -> String {
        try Self.execute("/usr/bin/git", ["-C", path.path] + arguments)
    }

    func run(_ arguments: String...) throws -> String { try run(arguments) }

    static func execute(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
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
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errData = (try? Data(contentsOf: errURL)) ?? Data()
        guard process.terminationStatus == 0 else {
            throw Failure(executable: executable, arguments: arguments, stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
