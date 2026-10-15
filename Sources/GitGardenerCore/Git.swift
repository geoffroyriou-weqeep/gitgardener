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
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Drain both pipes before waiting so a full pipe buffer cannot deadlock the child.
        let errData = ErrBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(executable: executable, arguments: arguments, stderr: String(decoding: errData.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class ErrBox: @unchecked Sendable { var data = Data() }
