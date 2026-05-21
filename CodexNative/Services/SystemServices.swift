import Foundation
import OSLog

struct CodexBinaryDiscovery: Equatable, Sendable {
    var url: URL?
    var checkedPaths: [String]
}

enum CodexBinaryLocator {
    static func discover(userConfiguredPath: String? = nil) -> CodexBinaryDiscovery {
        var checked: [String] = []

        if let userConfiguredPath, !userConfiguredPath.isEmpty {
            checked.append(userConfiguredPath)
            if FileManager.default.isExecutableFile(atPath: userConfiguredPath) {
                return CodexBinaryDiscovery(url: URL(fileURLWithPath: userConfiguredPath), checkedPaths: checked)
            }
        }

        if let path = runWhichCodex() {
            checked.append(path)
            if FileManager.default.isExecutableFile(atPath: path) {
                return CodexBinaryDiscovery(url: URL(fileURLWithPath: path), checkedPaths: checked)
            }
        }

        let bundledPath = "/Applications/Codex.app/Contents/Resources/codex"
        checked.append(bundledPath)
        if FileManager.default.isExecutableFile(atPath: bundledPath) {
            return CodexBinaryDiscovery(url: URL(fileURLWithPath: bundledPath), checkedPaths: checked)
        }

        return CodexBinaryDiscovery(url: nil, checkedPaths: checked)
    }

    private static func runWhichCodex() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["codex"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }
}

struct GitStatusSnapshot: Equatable, Sendable {
    var cwd: String
    var branch: String?
    var changedFiles: [String]

    static let empty = GitStatusSnapshot(cwd: "", branch: nil, changedFiles: [])
}

enum GitInspector {
    static func readStatus(cwd: String) async -> GitStatusSnapshot {
        async let branch = runGit(arguments: ["-C", cwd, "branch", "--show-current"])
        async let status = runGit(arguments: ["-C", cwd, "status", "--short"])

        let branchOutput = await branch?.trimmingCharacters(in: .whitespacesAndNewlines)
        let statusOutput = await status ?? ""
        let files = statusOutput
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return GitStatusSnapshot(cwd: cwd, branch: branchOutput?.isEmpty == false ? branchOutput : nil, changedFiles: files)
    }

    private static func runGit(arguments: [String]) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return nil
            }

            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        }.value
    }
}

extension Date {
    var shortCodexString: String {
        formatted(date: .numeric, time: .shortened)
    }
}
