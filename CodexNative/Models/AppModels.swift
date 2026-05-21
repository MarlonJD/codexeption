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

    var parentDisplayName: String? {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? nil : parent
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

    var isArchived: Bool {
        let normalized = status.lowercased()
        return normalized == "archived" || normalized == "archive"
    }
}

enum AuthStatus: Equatable, Sendable {
    case unknown
    case signedOut
    case signingIn(String)
    case signedIn(method: String)
    case unavailable(String)

    var title: String {
        switch self {
        case .unknown:
            "Hesap kontrol ediliyor"
        case .signedOut:
            "Giris gerekli"
        case .signingIn:
            "Giris bekleniyor"
        case .signedIn(let method):
            "\(method.uppercased()) bagli"
        case .unavailable:
            "Auth okunamadi"
        }
    }

    var detail: String {
        switch self {
        case .unknown:
            "Codex auth okunuyor"
        case .signedOut:
            "Codex hesabi bulunamadi"
        case .signingIn(let message):
            message
        case .signedIn:
            "Yerel Codex oturumu hazir"
        case .unavailable(let message):
            message
        }
    }

    var canStartTurns: Bool {
        if case .signedIn = self {
            return true
        }
        return false
    }
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

    var isActive: Bool {
        let normalized = status.lowercased()
        return !["completed", "failed", "cancelled", "canceled"].contains(normalized)
    }

    var isWritingAssistantMessage: Bool {
        items.contains { item in
            item.kind == .assistant && !item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
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

enum PermissionMode: String, CaseIterable, Identifiable, Sendable {
    case defaults
    case autoReview
    case fullAccess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaults:
            "Varsayilan izinler"
        case .autoReview:
            "Otomatik inceleme"
        case .fullAccess:
            "Tam erisim"
        }
    }

    var systemImage: String {
        switch self {
        case .defaults:
            "hand.raised"
        case .autoReview:
            "terminal"
        case .fullAccess:
            "shield"
        }
    }

    var approvalPolicy: String? {
        switch self {
        case .defaults:
            nil
        case .autoReview:
            "on-request"
        case .fullAccess:
            "never"
        }
    }

    var approvalsReviewer: String? {
        switch self {
        case .defaults, .fullAccess:
            nil
        case .autoReview:
            "auto_review"
        }
    }

    var sandboxMode: String? {
        switch self {
        case .defaults:
            nil
        case .autoReview:
            "workspace-write"
        case .fullAccess:
            "danger-full-access"
        }
    }

    var turnSandboxPolicy: SandboxPolicyDTO? {
        switch self {
        case .defaults, .autoReview:
            nil
        case .fullAccess:
            SandboxPolicyDTO(type: "dangerFullAccess")
        }
    }

    init(legacyApprovalPolicy: String) {
        switch legacyApprovalPolicy {
        case "never":
            self = .fullAccess
        case "on-request", "untrusted":
            self = .autoReview
        default:
            self = .defaults
        }
    }
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

    var changeSummary: LiveChangeSummary {
        LiveChangeSummary(threadID: threadID, turnID: turnID, files: LiveChangeSummary.parse(unifiedDiff: unifiedDiff))
    }
}

struct LiveChangeSummary: Equatable, Sendable {
    let threadID: String
    let turnID: String
    var files: [LiveFileChange]

    var id: String { "\(threadID)-\(turnID)" }
    var fileCount: Int { files.count }
    var additions: Int { files.reduce(0) { $0 + $1.additions } }
    var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
    var totalChangeCount: Int { additions + deletions + fileCount }

    static func parse(unifiedDiff: String) -> [LiveFileChange] {
        var changes: [LiveFileChange] = []
        var currentPath: String?
        var additions = 0
        var deletions = 0
        var state = LiveFileChange.State.modified

        func finishCurrentFile() {
            guard let currentPath else { return }
            changes.append(
                LiveFileChange(
                    path: currentPath,
                    additions: additions,
                    deletions: deletions,
                    state: state
                )
            )
        }

        for line in unifiedDiff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("diff --git ") {
                finishCurrentFile()
                currentPath = Self.pathFromDiffHeader(line)
                additions = 0
                deletions = 0
                state = .modified
                continue
            }

            guard currentPath != nil else { continue }

            if line.hasPrefix("new file mode") {
                state = .created
            } else if line.hasPrefix("deleted file mode") {
                state = .deleted
            } else if line.hasPrefix("rename from ") || line.hasPrefix("rename to ") {
                state = .renamed
            } else if line.hasPrefix("+++") || line.hasPrefix("---") {
                continue
            } else if line.hasPrefix("+") {
                additions += 1
            } else if line.hasPrefix("-") {
                deletions += 1
            }
        }

        finishCurrentFile()
        return changes
    }

    private static func pathFromDiffHeader(_ line: String) -> String {
        let parts = line.split(separator: " ")
        guard parts.count >= 4 else { return line }
        let rawPath = String(parts[3])
        return rawPath.hasPrefix("b/") ? String(rawPath.dropFirst(2)) : rawPath
    }
}

struct LiveFileChange: Identifiable, Equatable, Sendable {
    enum State: String, Equatable, Sendable {
        case created
        case modified
        case deleted
        case renamed
    }

    let path: String
    var additions: Int
    var deletions: Int
    var state: State

    var id: String { path }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var statusText: String {
        switch state {
        case .created:
            "olusturuluyor"
        case .modified:
            "degistiriliyor"
        case .deleted:
            "siliniyor"
        case .renamed:
            "yeniden adlandiriliyor"
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

    static let fallbackOptions: [ModelOption] = [
        ModelOption(
            id: "gpt-5.5",
            model: "gpt-5.5",
            displayName: "GPT-5.5",
            description: "Frontier model for complex coding, research, and real-world work.",
            supportedReasoningEfforts: ["low", "medium", "high", "xhigh"],
            defaultReasoningEffort: "medium",
            isDefault: true
        ),
        ModelOption(
            id: "gpt-5.4",
            model: "gpt-5.4",
            displayName: "gpt-5.4",
            description: "Strong model for everyday coding.",
            supportedReasoningEfforts: ["low", "medium", "high", "xhigh"],
            defaultReasoningEffort: "medium",
            isDefault: false
        ),
        ModelOption(
            id: "gpt-5.4-mini",
            model: "gpt-5.4-mini",
            displayName: "GPT-5.4-Mini",
            description: "Small, fast, and cost-efficient model for simpler coding tasks.",
            supportedReasoningEfforts: ["low", "medium", "high", "xhigh"],
            defaultReasoningEffort: "medium",
            isDefault: false
        )
    ]
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
