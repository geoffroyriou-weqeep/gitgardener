import Foundation

struct Git {
    struct Failure: Error, CustomStringConvertible {
        let arguments: [String]
        let stderr: String
        var description: String { "git \(arguments.joined(separator: " ")) failed: \(stderr)" }
    }

    let path: URL

    func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path.path] + arguments
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
            throw Failure(arguments: arguments, stderr: String(decoding: errData.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func run(_ arguments: String...) throws -> String { try run(arguments) }
}

private final class ErrBox: @unchecked Sendable { var data = Data() }
