import Foundation
import OSLog

struct CodexBinaryDiscovery: Equatable, Sendable {
    var url: URL?
    var checkedPaths: [String]
}

enum CodexBinaryLocator {
    private static let commonExecutablePaths = [
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        "/usr/bin/codex"
    ]

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

        for path in commonExecutablePaths where !checked.contains(path) {
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
        process.environment = ProcessEnvironment.withCommonPaths()

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

enum LocalCodexHistoryReader {
    static func readSummaries(limit: Int = 200) async -> [ThreadSummary] {
        await Task.detached(priority: .utility) {
            readSummariesSync(limit: limit)
        }.value
    }

    private static func readSummariesSync(limit: Int) -> [ThreadSummary] {
        let fileManager = FileManager.default
        let sessionsRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("sessions")

        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var summaries: [ThreadSummary] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if let summary = readSummary(url: url) {
                summaries.append(summary)
            }
        }

        return Array(summaries.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    private static func readSummary(url: URL) -> ThreadSummary? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: 512_000)) ?? Data()
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = text.split(separator: "\n", maxSplits: 120, omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return nil }

        var id: String?
        var cwd: String?
        var modelProvider = "openai"
        var createdAt: Date?
        var preview: String?

        for line in lines {
            guard let value = decodeLine(String(line)),
                  let object = value.objectValue else {
                continue
            }

            if object["type"]?.stringValue == "session_meta",
               let payload = object["payload"]?.objectValue {
                id = payload["id"]?.stringValue ?? id
                cwd = payload["cwd"]?.stringValue ?? cwd
                modelProvider = payload["model_provider"]?.stringValue ?? modelProvider
                createdAt = parseDate(payload["timestamp"]?.stringValue ?? object["timestamp"]?.stringValue) ?? createdAt
                continue
            }

            guard preview == nil,
                  object["type"]?.stringValue == "response_item",
                  let payload = object["payload"]?.objectValue,
                  payload["type"]?.stringValue == "message",
                  payload["role"]?.stringValue == "user" else {
                continue
            }

            let candidate = textContent(from: payload["content"]?.arrayValue ?? [])
            if isUserVisible(candidate) {
                preview = cleaned(candidate)
            }
        }

        guard let id else { return nil }
        let fallbackDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        let updatedAt = fallbackDate
        let created = createdAt ?? updatedAt
        let body = preview ?? url.deletingPathExtension().lastPathComponent
        let title = titleFromPreview(body)

        return ThreadSummary(
            id: id,
            title: title,
            preview: body,
            cwd: cwd ?? fileManagerHomePath(),
            modelProvider: modelProvider,
            status: "local",
            createdAt: created,
            updatedAt: updatedAt
        )
    }

    private static func decodeLine(_ line: String) -> JSONValue? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder.codex.decode(JSONValue.self, from: data)
    }

    private static func textContent(from content: [JSONValue]) -> String {
        content.compactMap { item -> String? in
            guard let object = item.objectValue else { return item.stringValue }
            guard object["type"]?.stringValue == "input_text" else { return nil }
            return object["text"]?.stringValue
        }
        .joined(separator: "\n")
    }

    private static func isUserVisible(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.hasPrefix("<environment_context>") else { return false }
        guard !trimmed.hasPrefix("<developer_instructions>") else { return false }
        guard !trimmed.hasPrefix("<permissions instructions>") else { return false }
        guard !trimmed.hasPrefix("<app-context>") else { return false }
        guard !trimmed.hasPrefix("<skills_instructions>") else { return false }
        return true
    }

    private static func cleaned(_ text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(singleLine.prefix(260))
    }

    private static func titleFromPreview(_ preview: String) -> String {
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Adsiz sohbet" }
        return String(trimmed.prefix(80))
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static func fileManagerHomePath() -> String {
        FileManager.default.homeDirectoryForCurrentUser.path
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
