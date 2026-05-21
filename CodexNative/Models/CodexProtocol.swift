import Foundation

struct InitializeParams: Encodable, Sendable {
    let clientInfo: ClientInfo
    let capabilities: InitializeCapabilities
}

struct ClientInfo: Encodable, Sendable {
    let name: String
    let title: String?
    let version: String
}

struct InitializeCapabilities: Encodable, Sendable {
    let experimentalApi: Bool
    let requestAttestation: Bool
    let optOutNotificationMethods: [String]?
}

struct InitializeResponse: Decodable, Sendable {
    let userAgent: String
    let codexHome: String
    let platformFamily: String
    let platformOs: String
}

struct ThreadListParams: Encodable, Sendable {
    var cursor: String?
    var limit: Int?
    var sortKey: String?
    var sortDirection: String?
    var archived: Bool?
    var cwd: String?
    var useStateDbOnly: Bool?
    var searchTerm: String?
}

struct ThreadListResponseDTO: Decodable, Sendable {
    let data: [ThreadDTO]
    let nextCursor: String?
    let backwardsCursor: String?
}

struct ThreadReadParams: Encodable, Sendable {
    let threadId: String
    let includeTurns: Bool
}

struct ThreadReadResponseDTO: Decodable, Sendable {
    let thread: ThreadDTO
}

struct ThreadStartParams: Encodable, Sendable {
    var model: String?
    var modelProvider: String?
    var cwd: String?
    var approvalPolicy: String?
    var approvalsReviewer: String?
    var sandbox: String?
    var ephemeral: Bool?
    var sessionStartSource: String?
}

struct ThreadStartResponseDTO: Decodable, Sendable {
    let thread: ThreadDTO
    let model: String
    let modelProvider: String
    let cwd: String
    let approvalPolicy: String
    let reasoningEffort: String?
}

struct ThreadResumeParams: Encodable, Sendable {
    let threadId: String
    var model: String?
    var cwd: String?
    var approvalPolicy: String?
}

struct ThreadResumeResponseDTO: Decodable, Sendable {
    let thread: ThreadDTO
    let model: String
    let modelProvider: String
    let cwd: String
    let approvalPolicy: String
    let reasoningEffort: String?
}

struct ThreadArchiveParams: Encodable, Sendable {
    let threadId: String
}

struct ThreadSetNameParams: Encodable, Sendable {
    let threadId: String
    let name: String
}

struct TurnStartParams: Encodable, Sendable {
    let threadId: String
    let input: [UserInputDTO]
    var cwd: String?
    var approvalPolicy: String?
    var approvalsReviewer: String?
    var sandboxPolicy: SandboxPolicyDTO?
    var model: String?
    var effort: String?
}

struct SandboxPolicyDTO: Codable, Equatable, Sendable {
    let type: String
}

struct TurnStartResponseDTO: Decodable, Sendable {
    let turn: TurnDTO
}

struct TurnInterruptParams: Encodable, Sendable {
    let threadId: String
    let turnId: String
}

struct ModelListParams: Encodable, Sendable {
    var cursor: String?
    var limit: Int?
    var includeHidden: Bool?
}

struct ModelListResponseDTO: Decodable, Sendable {
    let data: [ModelDTO]
    let nextCursor: String?
}

struct ConfigReadParams: Encodable, Sendable {
    let includeLayers: Bool
    var cwd: String?
}

struct ConfigReadResponseDTO: Decodable, Sendable {
    let config: JSONValue
    let origins: [String: JSONValue]?
    let layers: [JSONValue]?
}

struct GetAuthStatusParams: Encodable, Sendable {
    let includeToken: Bool?
    let refreshToken: Bool?
}

struct GetAuthStatusResponseDTO: Decodable, Sendable {
    let authMethod: String?
    let authToken: String?
    let requiresOpenaiAuth: Bool?

    var status: AuthStatus {
        if let authMethod, !authMethod.isEmpty {
            return .signedIn(method: authMethod)
        }
        return .signedOut
    }
}

struct LoginAccountParams: Encodable, Sendable {
    let type: String
    var codexStreamlinedLogin: Bool?

    static var chatGPT: LoginAccountParams {
        LoginAccountParams(type: "chatgpt", codexStreamlinedLogin: true)
    }
}

struct LoginAccountResponseDTO: Decodable, Sendable {
    let type: String
    let loginId: String?
    let authUrl: String?
    let verificationUrl: String?
    let userCode: String?

    var loginURL: URL? {
        (authUrl ?? verificationUrl).flatMap(URL.init(string:))
    }
}

struct UserInputDTO: Codable, Equatable, Sendable {
    let type: String
    var text: String?
    var textElements: [JSONValue]?
    var detail: String?
    var url: String?
    var path: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case textElements = "text_elements"
        case detail
        case url
        case path
        case name
    }

    static func text(_ text: String) -> UserInputDTO {
        UserInputDTO(type: "text", text: text, textElements: [], detail: nil, url: nil, path: nil, name: nil)
    }

    static func localImage(path: String) -> UserInputDTO {
        UserInputDTO(type: "localImage", text: nil, textElements: nil, detail: nil, url: nil, path: path, name: nil)
    }

    static func mention(name: String, path: String) -> UserInputDTO {
        UserInputDTO(type: "mention", text: nil, textElements: nil, detail: nil, url: nil, path: path, name: name)
    }
}

struct ThreadDTO: Decodable, Sendable {
    let id: String
    let sessionId: String
    let preview: String
    let ephemeral: Bool
    let modelProvider: String
    let createdAt: Double
    let updatedAt: Double
    let status: String
    let path: String?
    let cwd: String
    let cliVersion: String?
    let name: String?
    let turns: [TurnDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId
        case preview
        case ephemeral
        case modelProvider
        case createdAt
        case updatedAt
        case status
        case path
        case cwd
        case cliVersion
        case name
        case turns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? id
        preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? ""
        ephemeral = try container.decodeIfPresent(Bool.self, forKey: .ephemeral) ?? false
        modelProvider = try container.decodeIfPresent(String.self, forKey: .modelProvider) ?? "openai"
        createdAt = try container.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        updatedAt = try container.decodeIfPresent(Double.self, forKey: .updatedAt) ?? createdAt
        status = try container.decodeFlexibleString(forKey: .status) ?? "unknown"
        path = try container.decodeIfPresent(String.self, forKey: .path)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd) ?? FileManager.default.homeDirectoryForCurrentUser.path
        cliVersion = try container.decodeIfPresent(String.self, forKey: .cliVersion)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        turns = try container.decodeIfPresent([TurnDTO].self, forKey: .turns) ?? []
    }

    var summary: ThreadSummary {
        ThreadSummary(
            id: id,
            title: (name?.isEmpty == false ? name : nil) ?? (preview.isEmpty ? "Adsiz sohbet" : preview),
            preview: preview,
            cwd: cwd,
            modelProvider: modelProvider,
            status: status,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }

    var detail: ThreadDetail {
        ThreadDetail(id: id, summary: summary, turns: turns.map(\.model))
    }
}

struct TurnDTO: Decodable, Sendable {
    let id: String
    let items: [JSONValue]
    let status: String
    let startedAt: Double?
    let completedAt: Double?
    let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case items
        case status
        case startedAt
        case completedAt
        case durationMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        items = try container.decodeIfPresent([JSONValue].self, forKey: .items) ?? []
        status = try container.decodeFlexibleString(forKey: .status) ?? "unknown"
        startedAt = try container.decodeIfPresent(Double.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Double.self, forKey: .completedAt)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
    }

    var model: CodexTurn {
        CodexTurn(
            id: id,
            status: status,
            items: items.map { TranscriptItem.fromThreadItem($0) },
            startedAt: startedAt.map(Date.init(timeIntervalSince1970:)),
            completedAt: completedAt.map(Date.init(timeIntervalSince1970:)),
            durationMs: durationMs
        )
    }
}

struct ModelDTO: Decodable, Sendable {
    let id: String
    let model: String
    let displayName: String
    let description: String
    let hidden: Bool
    let supportedReasoningEfforts: [String]
    let defaultReasoningEffort: String
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case displayName
        case description
        case hidden
        case supportedReasoningEfforts
        case defaultReasoningEffort
        case isDefault
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? id
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? id
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        supportedReasoningEfforts = try container.decodeIfPresent([ReasoningEffortDTO].self, forKey: .supportedReasoningEfforts)?.map(\.value) ?? []
        defaultReasoningEffort = try container.decodeFlexibleString(forKey: .defaultReasoningEffort) ?? "medium"
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }

    var option: ModelOption {
        ModelOption(
            id: id,
            model: model,
            displayName: displayName,
            description: description,
            supportedReasoningEfforts: supportedReasoningEfforts,
            defaultReasoningEffort: defaultReasoningEffort,
            isDefault: isDefault
        )
    }
}

struct ReasoningEffortDTO: Decodable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(String.self) {
            value = raw
        } else if let object = try? container.decode([String: JSONValue].self) {
            value = object["reasoningEffort"]?.stringValue
                ?? object["effort"]?.stringValue
                ?? object["value"]?.stringValue
                ?? object["id"]?.stringValue
                ?? "medium"
        } else {
            value = "medium"
        }
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) throws -> String? {
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return value
        }
        guard let value = try decodeIfPresent(JSONValue.self, forKey: key) else {
            return nil
        }
        switch value {
        case .string(let string):
            return string
        case .object(let object):
            return object["type"]?.stringValue ?? object["status"]?.stringValue ?? object["kind"]?.stringValue
        case .bool(let bool):
            return String(bool)
        case .number(let number):
            return String(number)
        case .null, .array:
            return nil
        }
    }
}

extension TranscriptItem {
    static func fromThreadItem(_ value: JSONValue) -> TranscriptItem {
        let object = value.objectValue ?? [:]
        let type = object["type"]?.stringValue ?? "unknown"
        let id = object["id"]?.stringValue ?? UUID().uuidString

        switch type {
        case "userMessage":
            let content = object["content"]?.arrayValue ?? []
            let body = content.compactMap { input -> String? in
                guard let inputObject = input.objectValue else { return nil }
                switch inputObject["type"]?.stringValue {
                case "text":
                    return inputObject["text"]?.stringValue
                case "localImage":
                    return "[Gorsel] \(inputObject["path"]?.stringValue ?? "")"
                case "image":
                    return "[Gorsel] \(inputObject["url"]?.stringValue ?? "")"
                case "mention":
                    return "@\(inputObject["name"]?.stringValue ?? inputObject["path"]?.stringValue ?? "")"
                default:
                    return nil
                }
            }.joined(separator: "\n")
            return TranscriptItem(id: id, kind: .user, title: "Sen", body: body, detail: nil, timestamp: nil)

        case "agentMessage":
            let body = object["text"]?.stringValue ?? Self.textContent(from: object["content"]?.arrayValue ?? [])
            return TranscriptItem(id: id, kind: .assistant, title: "Codex", body: body, detail: nil, timestamp: nil)

        case "reasoning":
            let summaries = object["summary"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let content = object["content"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return TranscriptItem(id: id, kind: .reasoning, title: "Akil yurutme", body: (summaries + content).joined(separator: "\n"), detail: nil, timestamp: nil)

        case "commandExecution":
            let command = object["command"]?.stringValue ?? ""
            let output = object["aggregatedOutput"]?.stringValue
            return TranscriptItem(id: id, kind: .command, title: command, body: output ?? "", detail: object["cwd"]?.stringValue, timestamp: nil)

        case "fileChange":
            let changes = object["changes"]?.arrayValue ?? []
            let files = changes.compactMap { change -> String? in
                let object = change.objectValue ?? [:]
                return object["path"]?.stringValue ?? object["file"]?.stringValue
            }
            return TranscriptItem(id: id, kind: .fileChange, title: "Dosya degisikligi", body: files.joined(separator: "\n"), detail: object["status"]?.stringValue, timestamp: nil)

        case "mcpToolCall", "dynamicToolCall", "webSearch":
            let title = object["tool"]?.stringValue ?? object["query"]?.stringValue ?? type
            return TranscriptItem(id: id, kind: .tool, title: title, body: value.debugSummary, detail: nil, timestamp: nil)

        default:
            return TranscriptItem(id: id, kind: .system, title: type, body: value.debugSummary, detail: nil, timestamp: nil)
        }
    }

    private static func textContent(from content: [JSONValue]) -> String {
        content.compactMap { item -> String? in
            guard let object = item.objectValue else { return item.stringValue }
            return object["text"]?.stringValue
                ?? object["content"]?.stringValue
                ?? object["message"]?.stringValue
        }
        .joined(separator: "\n")
    }
}

extension JSONValue {
    var debugSummary: String {
        guard let data = try? JSONEncoder.codex.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}
