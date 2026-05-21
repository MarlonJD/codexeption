import Foundation
import SwiftData

struct Project: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    var displayName: String
    var threadCount: Int

    init(path: String, threadCount: Int = 0) {
        self.id = path
        self.path = path
        self.displayName = URL(fileURLWithPath: path).lastPathComponent
        self.threadCount = threadCount
    }
}

struct ThreadSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let preview: String
    let cwd: String
    let modelProvider: String
    let status: String
    let createdAt: Date
    let updatedAt: Date
}

struct ThreadDetail: Identifiable, Sendable {
    let id: String
    var summary: ThreadSummary
    var turns: [CodexTurn]

    var transcriptItems: [TranscriptItem] {
        turns.flatMap(\.items)
    }
}

struct CodexTurn: Identifiable, Sendable {
    let id: String
    var status: String
    var items: [TranscriptItem]
    var startedAt: Date?
    var completedAt: Date?
    var durationMs: Int?
}

enum TranscriptKind: String, Codable, Sendable {
    case user
    case assistant
    case reasoning
    case command
    case fileChange
    case tool
    case system
}

struct TranscriptItem: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var kind: TranscriptKind
    var title: String?
    var body: String
    var detail: String?
    var timestamp: Date?
}

enum ApprovalKind: String, Codable, Sendable {
    case commandExecution
    case fileChange
    case permissions
    case unknown
}

struct ApprovalRequest: Identifiable, Equatable, Sendable {
    let requestID: RPCID
    let kind: ApprovalKind
    let method: String
    let threadID: String?
    let turnID: String?
    let itemID: String?
    let title: String
    let detail: String
    let cwd: String?

    var id: String { requestID.description }
}

enum ApprovalDecision: String, Codable, CaseIterable, Sendable {
    case accept
    case acceptForSession
    case decline
    case cancel
}

struct DiffSnapshot: Equatable, Sendable {
    let threadID: String
    let turnID: String
    var unifiedDiff: String

    var filePaths: [String] {
        unifiedDiff
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                guard line.hasPrefix("diff --git ") else { return nil }
                let parts = line.split(separator: " ")
                guard parts.count >= 4 else { return nil }
                let raw = String(parts[3])
                return raw.hasPrefix("b/") ? String(raw.dropFirst(2)) : raw
            }
    }
}

struct ModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let model: String
    let displayName: String
    let description: String
    let supportedReasoningEfforts: [String]
    let defaultReasoningEffort: String
    let isDefault: Bool
}

struct AppSettings: Equatable, Sendable {
    var codexBinaryPath: String?
    var selectedModel: String?
    var selectedReasoningEffort: String = "medium"
    var approvalPolicy: String = "on-request"
    var inspectorVisible: Bool = true
}

@Model
final class BookmarkRecord {
    @Attribute(.unique) var path: String
    var displayName: String
    var createdAt: Date

    init(path: String, displayName: String? = nil, createdAt: Date = .now) {
        self.path = path
        self.displayName = displayName ?? URL(fileURLWithPath: path).lastPathComponent
        self.createdAt = createdAt
    }
}

@Model
final class AppSettingsRecord {
    @Attribute(.unique) var key: String
    var codexBinaryPath: String?
    var selectedProjectPath: String?
    var selectedThreadID: String?
    var selectedModel: String?
    var selectedReasoningEffort: String
    var approvalPolicy: String
    var inspectorVisible: Bool

    init(
        key: String = "default",
        codexBinaryPath: String? = nil,
        selectedProjectPath: String? = nil,
        selectedThreadID: String? = nil,
        selectedModel: String? = nil,
        selectedReasoningEffort: String = "medium",
        approvalPolicy: String = "on-request",
        inspectorVisible: Bool = true
    ) {
        self.key = key
        self.codexBinaryPath = codexBinaryPath
        self.selectedProjectPath = selectedProjectPath
        self.selectedThreadID = selectedThreadID
        self.selectedModel = selectedModel
        self.selectedReasoningEffort = selectedReasoningEffort
        self.approvalPolicy = approvalPolicy
        self.inspectorVisible = inspectorVisible
    }
}

@Model
final class ThreadCacheRecord {
    @Attribute(.unique) var threadID: String
    var cwd: String
    var title: String
    var updatedAt: Date

    init(threadID: String, cwd: String, title: String, updatedAt: Date) {
        self.threadID = threadID
        self.cwd = cwd
        self.title = title
        self.updatedAt = updatedAt
    }
}
