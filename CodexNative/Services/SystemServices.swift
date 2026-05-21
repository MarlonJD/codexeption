import Foundation
import OSLog
import SQLite3

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
    private static let tailReadBytes: UInt64 = 1_250_000
    private static let detailItemLimit = 120
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func readSummaries(limit: Int = 200) async -> [ThreadSummary] {
        await Task.detached(priority: .utility) {
            readSummariesSync(limit: limit)
        }.value
    }

    static func readDetail(id: String) async -> ThreadDetail? {
        await Task.detached(priority: .utility) {
            guard let url = sessionFileURL(id: id) else { return nil }
            return readDetail(url: url, itemLimit: detailItemLimit)
        }.value
    }

    private static func readSummariesSync(limit: Int) -> [ThreadSummary] {
        let indexed = readIndexedSummaries(limit: limit)
        if !indexed.isEmpty {
            return indexed
        }

        let archivedIDs = archivedThreadIDs()
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var summaries: [ThreadSummary] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if let summary = readSummary(url: url), !archivedIDs.contains(summary.id) {
                summaries.append(summary)
            }
        }

        return Array(summaries.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    private static var sessionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("sessions")
    }

    private static func sessionFileURL(id: String) -> URL? {
        if let path = rolloutPath(threadID: id) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if url.lastPathComponent.contains(id) {
                return url
            }
        }
        return nil
    }

    private static var stateDBURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("state_5.sqlite")
    }

    private static func readIndexedSummaries(limit: Int) -> [ThreadSummary] {
        withStateDB { database in
            let sql = """
                SELECT id, title, preview, cwd, model_provider, created_at_ms, updated_at_ms
                FROM threads
                WHERE archived = 0
                ORDER BY updated_at_ms DESC, id DESC
                LIMIT ?
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, Int32(limit))
            var summaries: [ThreadSummary] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = sqliteText(statement, 0),
                      let cwd = sqliteText(statement, 3) else {
                    continue
                }
                let title = sqliteText(statement, 1) ?? "Adsiz sohbet"
                let preview = sqliteText(statement, 2) ?? ""
                let modelProvider = sqliteText(statement, 4) ?? "openai"
                let createdAt = dateFromMilliseconds(sqlite3_column_int64(statement, 5))
                let updatedAt = dateFromMilliseconds(sqlite3_column_int64(statement, 6))
                summaries.append(
                    ThreadSummary(
                        id: id,
                        title: title.isEmpty ? titleFromPreview(preview) : title,
                        preview: preview,
                        cwd: cwd,
                        modelProvider: modelProvider,
                        status: "local",
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    )
                )
            }
            return summaries
        } ?? []
    }

    private static func archivedThreadIDs() -> Set<String> {
        let indexed: Set<String> = withStateDB { database in
            let sql = "SELECT id FROM threads WHERE archived != 0"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return Set<String>() }
            defer { sqlite3_finalize(statement) }

            var ids = Set<String>()
            while sqlite3_step(statement) == SQLITE_ROW {
                if let id = sqliteText(statement, 0) {
                    ids.insert(id)
                }
            }
            return ids
        } ?? Set<String>()

        guard indexed.isEmpty else { return indexed }
        let archivedRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("archived_sessions")
        guard let enumerator = FileManager.default.enumerator(at: archivedRoot, includingPropertiesForKeys: nil) else {
            return []
        }

        var ids = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if let id = sessionID(from: url) {
                ids.insert(id)
            }
        }
        return ids
    }

    private static func rolloutPath(threadID: String) -> String? {
        withStateDB { database in
            let sql = "SELECT rollout_path FROM threads WHERE id = ? LIMIT 1"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, threadID, -1, sqliteTransient)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return sqliteText(statement, 0)
        } ?? nil
    }

    private static func withStateDB<T>(_ body: (OpaquePointer) -> T) -> T? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(stateDBURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }
        return body(database)
    }

    private static func sqliteText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private static func dateFromMilliseconds(_ raw: Int64) -> Date {
        guard raw > 0 else { return .distantPast }
        return Date(timeIntervalSince1970: TimeInterval(raw) / 1000)
    }

    private static func sessionID(from url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let range = name.range(of: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: .regularExpression) else {
            return nil
        }
        return String(name[range])
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
        var title: String?

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

            if object["type"]?.stringValue == "event_msg",
               let payload = object["payload"]?.objectValue,
               payload["type"]?.stringValue == "thread_name_updated",
               let threadName = payload["thread_name"]?.stringValue,
               !threadName.isEmpty {
                title = threadName
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
        let resolvedTitle = title ?? titleFromPreview(body)

        return ThreadSummary(
            id: id,
            title: resolvedTitle,
            preview: body,
            cwd: cwd ?? fileManagerHomePath(),
            modelProvider: modelProvider,
            status: "local",
            createdAt: created,
            updatedAt: updatedAt
        )
    }

    private static func readDetail(url: URL, itemLimit: Int) -> ThreadDetail? {
        guard let summary = readSummary(url: url),
              let text = readTailText(url: url, maxBytes: tailReadBytes) else {
            return nil
        }

        var turns: [CodexTurn] = []
        var currentTurnID: String?
        var itemIndex = 0

        func ensureTurn(id: String, timestamp: Date?) {
            if !turns.contains(where: { $0.id == id }) {
                turns.append(CodexTurn(id: id, status: "completed", items: [], startedAt: timestamp, completedAt: nil, durationMs: nil))
            }
            currentTurnID = id
        }

        func appendItem(_ item: TranscriptItem, timestamp: Date?) {
            let turnID = currentTurnID ?? "local-turn-\(turns.count + 1)"
            ensureTurn(id: turnID, timestamp: timestamp)
            guard let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
            turns[index].items.append(item)
            turns[index].completedAt = timestamp ?? turns[index].completedAt
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let value = decodeLine(String(line)),
                  let object = value.objectValue else {
                continue
            }

            let timestamp = parseDate(object["timestamp"]?.stringValue)
            if object["type"]?.stringValue == "turn_context",
               let payload = object["payload"]?.objectValue,
               let turnID = payload["turn_id"]?.stringValue {
                ensureTurn(id: turnID, timestamp: timestamp)
                continue
            }

            guard object["type"]?.stringValue == "response_item",
                  let payload = object["payload"]?.objectValue else {
                continue
            }

            itemIndex += 1
            if let item = transcriptItem(from: payload, fallbackID: "local-item-\(itemIndex)", timestamp: timestamp) {
                if item.kind == .user, turns.last?.items.isEmpty == false {
                    currentTurnID = "local-turn-\(turns.count + 1)"
                }
                appendItem(item, timestamp: timestamp)
            }
        }

        turns.removeAll { $0.items.isEmpty }
        return ThreadDetail(id: summary.id, summary: summary, turns: trimTurns(turns, itemLimit: itemLimit))
    }

    private static func readTailText(url: URL, maxBytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > maxBytes ? size - maxBytes : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        guard var text = String(data: data, encoding: .utf8) else { return nil }

        if offset > 0, let newline = text.firstIndex(of: "\n") {
            text.removeSubrange(text.startIndex...newline)
        }
        return text
    }

    private static func trimTurns(_ turns: [CodexTurn], itemLimit: Int) -> [CodexTurn] {
        guard itemLimit > 0 else { return [] }

        var remaining = itemLimit
        var result: [CodexTurn] = []
        for turn in turns.reversed() {
            guard remaining > 0 else { break }
            let items = Array(turn.items.suffix(remaining))
            guard !items.isEmpty else { continue }
            var trimmedTurn = turn
            trimmedTurn.items = items
            result.append(trimmedTurn)
            remaining -= items.count
        }
        return result.reversed()
    }

    private static func transcriptItem(from payload: [String: JSONValue], fallbackID: String, timestamp: Date?) -> TranscriptItem? {
        let type = payload["type"]?.stringValue ?? "unknown"
        let id = payload["id"]?.stringValue ?? fallbackID

        switch type {
        case "message":
            let role = payload["role"]?.stringValue
            let body = textContent(from: payload["content"]?.arrayValue ?? [])
            guard role != "user" || isUserVisible(body) else { return nil }
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return TranscriptItem(
                id: id,
                kind: role == "assistant" ? .assistant : .user,
                title: role == "assistant" ? "Codex" : "Sen",
                body: body,
                detail: nil,
                timestamp: timestamp
            )

        case "reasoning":
            let body = reasoningText(from: payload)
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return TranscriptItem(id: id, kind: .reasoning, title: "Akil yurutme", body: body, detail: nil, timestamp: timestamp)

        case "function_call":
            let name = payload["name"]?.stringValue ?? payload["tool"]?.stringValue ?? "Tool"
            let body = payload["arguments"]?.stringValue ?? payload.debugDescription
            return TranscriptItem(id: id, kind: .tool, title: name, body: body, detail: nil, timestamp: timestamp)

        case "function_call_output":
            let body = payload["output"]?.stringValue ?? payload.debugDescription
            return TranscriptItem(id: id, kind: .command, title: "Tool output", body: body, detail: nil, timestamp: timestamp)

        default:
            return nil
        }
    }

    private static func reasoningText(from payload: [String: JSONValue]) -> String {
        let summary = payload["summary"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let content = payload["content"]?.arrayValue?.compactMap(\.stringValue) ?? []
        return (summary + content).joined(separator: "\n")
    }

    private static func decodeLine(_ line: String) -> JSONValue? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder.codex.decode(JSONValue.self, from: data)
    }

    private static func textContent(from content: [JSONValue]) -> String {
        content.compactMap { item -> String? in
            guard let object = item.objectValue else { return item.stringValue }
            guard ["input_text", "output_text", "text"].contains(object["type"]?.stringValue) else { return nil }
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
