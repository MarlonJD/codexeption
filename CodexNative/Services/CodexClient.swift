import Foundation
import OSLog

enum CodexClientError: LocalizedError, Sendable {
    case missingBinary
    case notConnected

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            "Codex ikilisi bulunamadi."
        case .notConnected:
            "Codex app-server baglantisi hazir degil."
        }
    }
}

enum CodexEvent: Sendable {
    case notification(method: String, params: JSONValue?)
    case approvalRequested(ApprovalRequest)
    case threadStarted(ThreadSummary)
    case threadStatusChanged(threadID: String, status: String)
    case turnStarted(threadID: String, turn: CodexTurn)
    case turnCompleted(threadID: String, turn: CodexTurn)
    case itemUpdated(threadID: String, turnID: String, item: TranscriptItem)
    case assistantDelta(threadID: String, turnID: String, itemID: String, delta: String)
    case commandOutputDelta(threadID: String, turnID: String, itemID: String, delta: String)
    case diffUpdated(DiffSnapshot)
    case turnError(threadID: String, turnID: String?, message: String)
    case accountUpdated
    case accountLoginCompleted(loginID: String?, success: Bool, error: String?)
    case terminated(Int32)
    case unknown(method: String?, params: JSONValue?)
}

actor CodexClient {
    nonisolated let events: AsyncStream<CodexEvent>
    private static let startupTimeoutNanoseconds: UInt64 = 25_000_000_000
    private static let requestTimeoutNanoseconds: UInt64 = 25_000_000_000
    private static let mutationTimeoutNanoseconds: UInt64 = 45_000_000_000

    private let binaryURL: URL
    private let idleShutdownNanoseconds: UInt64
    private let logger = Logger(subsystem: "CodexNative", category: "Client")
    private let eventContinuation: AsyncStream<CodexEvent>.Continuation
    private var transport: LineJSONRPCTransport?
    private var eventPump: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var activeTurnIDs: Set<String> = []
    private var pendingApprovalIDs: Set<RPCID> = []
    private var pendingLoginIDs: Set<String> = []
    private var initialized = false

    init(binaryURL: URL, idleShutdownSeconds: UInt64 = 60) {
        self.binaryURL = binaryURL
        self.idleShutdownNanoseconds = idleShutdownSeconds * 1_000_000_000
        var continuation: AsyncStream<CodexEvent>.Continuation?
        self.events = AsyncStream { streamContinuation in
            continuation = streamContinuation
        }
        self.eventContinuation = continuation!
    }

    func connect() async throws {
        if initialized, transport != nil { return }
        idleTask?.cancel()

        let transport = LineJSONRPCTransport(binaryURL: binaryURL)
        self.transport = transport
        do {
            try await transport.start()
            startEventPump(transport)

            let params = InitializeParams(
                clientInfo: ClientInfo(name: "codex-native-macos", title: "Codex Native", version: "0.1.0"),
                capabilities: InitializeCapabilities(
                    experimentalApi: true,
                    requestAttestation: false,
                    optOutNotificationMethods: nil
                )
            )
            let _: InitializeResponse = try await transport.request(
                "initialize",
                params: params,
                response: InitializeResponse.self,
                timeoutNanoseconds: Self.startupTimeoutNanoseconds
            )
            try await transport.notify("initialized")
            initialized = true
            scheduleIdleShutdownIfQuiet()
        } catch {
            initialized = false
            eventPump?.cancel()
            eventPump = nil
            if self.transport === transport {
                self.transport = nil
            }
            await transport.stop()
            throw error
        }
    }

    func disconnect() async {
        initialized = false
        idleTask?.cancel()
        eventPump?.cancel()
        eventPump = nil
        await transport?.stop()
        transport = nil
    }

    func listThreads(cwd: String? = nil, searchTerm: String? = nil) async throws -> [ThreadSummary] {
        try await connect()
        let response: ThreadListResponseDTO = try await requireTransport().request(
            "thread/list",
            params: ThreadListParams(
                cursor: nil,
                limit: 200,
                sortKey: "updated_at",
                sortDirection: "desc",
                archived: false,
                cwd: cwd,
                useStateDbOnly: false,
                searchTerm: searchTerm
            ),
            response: ThreadListResponseDTO.self,
            timeoutNanoseconds: Self.requestTimeoutNanoseconds
        )
        scheduleIdleShutdownIfQuiet()
        return response.data
            .map(\.summary)
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                lhs.updatedAt == rhs.updatedAt ? lhs.title < rhs.title : lhs.updatedAt > rhs.updatedAt
            }
    }

    func readThread(id: String) async throws -> ThreadDetail {
        try await connect()
        let response: ThreadReadResponseDTO = try await requireTransport().request(
            "thread/read",
            params: ThreadReadParams(threadId: id, includeTurns: true),
            response: ThreadReadResponseDTO.self,
            timeoutNanoseconds: Self.requestTimeoutNanoseconds
        )
        scheduleIdleShutdownIfQuiet()
        return response.thread.detail
    }

    func startThread(cwd: String?, model: String?, permissionMode: PermissionMode) async throws -> ThreadSummary {
        try await connect()
        let response: ThreadStartResponseDTO = try await requireTransport().request(
            "thread/start",
            params: ThreadStartParams(
                model: model,
                modelProvider: nil,
                cwd: cwd,
                approvalPolicy: permissionMode.approvalPolicy,
                approvalsReviewer: permissionMode.approvalsReviewer,
                sandbox: permissionMode.sandboxMode,
                ephemeral: false,
                sessionStartSource: nil
            ),
            response: ThreadStartResponseDTO.self,
            timeoutNanoseconds: Self.mutationTimeoutNanoseconds
        )
        scheduleIdleShutdownIfQuiet()
        return response.thread.summary
    }

    func resumeThread(id: String, model: String?, approvalPolicy: String?) async throws -> ThreadDetail {
        try await connect()
        let response: ThreadResumeResponseDTO = try await requireTransport().request(
            "thread/resume",
            params: ThreadResumeParams(threadId: id, model: model, cwd: nil, approvalPolicy: approvalPolicy),
            response: ThreadResumeResponseDTO.self,
            timeoutNanoseconds: Self.requestTimeoutNanoseconds
        )
        scheduleIdleShutdownIfQuiet()
        return response.thread.detail
    }

    func archiveThread(id: String) async throws {
        try await connect()
        let _: EmptyResponse = try await requireTransport().request(
            "thread/archive",
            params: ThreadArchiveParams(threadId: id),
            response: EmptyResponse.self,
            timeoutNanoseconds: Self.mutationTimeoutNanoseconds
        )
        scheduleIdleShutdownIfQuiet()
    }

    func setThreadName(id: String, name: String) async throws {
        try await connect()
        let _: EmptyResponse = try await requireTransport().request(
            "thread/name/set",
            params: ThreadSetNameParams(threadId: id, name: name),
            response: EmptyResponse.self,
            timeoutNanoseconds: Self.mutationTimeoutNanoseconds
        )
        scheduleIdleShutdownIfQuiet()
    }

    func startTurn(threadID: String, input: [UserInputDTO], cwd: String?, model: String?, effort: String?, permissionMode: PermissionMode) async throws -> CodexTurn {
        try await connect()
        let response: TurnStartResponseDTO = try await requireTransport().request(
            "turn/start",
            params: TurnStartParams(
                threadId: threadID,
                input: input,
                cwd: cwd,
                approvalPolicy: permissionMode.approvalPolicy,
                approvalsReviewer: permissionMode.approvalsReviewer,
                sandboxPolicy: permissionMode.turnSandboxPolicy,
                model: model,
                effort: effort
            ),
            response: TurnStartResponseDTO.self,
            timeoutNanoseconds: Self.mutationTimeoutNanoseconds
        )
        activeTurnIDs.insert(response.turn.id)
        return response.turn.model
    }

    func interruptTurn(threadID: String, turnID: String) async throws {
        try await connect()
        let _: EmptyResponse = try await requireTransport().request(
            "turn/interrupt",
            params: TurnInterruptParams(threadId: threadID, turnId: turnID),
            response: EmptyResponse.self,
            timeoutNanoseconds: Self.mutationTimeoutNanoseconds
        )
        activeTurnIDs.remove(turnID)
        scheduleIdleShutdownIfQuiet()
    }

    func listModels() async throws -> [ModelOption] {
        try await connect()
        let response: ModelListResponseDTO = try await requireTransport().request(
            "model/list",
            params: ModelListParams(cursor: nil, limit: nil, includeHidden: false),
            response: ModelListResponseDTO.self,
            timeoutNanoseconds: Self.requestTimeoutNanoseconds
        )
        scheduleIdleShutdownIfQuiet()
        return response.data.filter { !$0.hidden }.map(\.option)
    }

    func readConfig(cwd: String? = nil) async throws -> ConfigReadResponseDTO {
        try await connect()
        let response: ConfigReadResponseDTO = try await requireTransport().request(
            "config/read",
            params: ConfigReadParams(includeLayers: true, cwd: cwd),
            response: ConfigReadResponseDTO.self,
            timeoutNanoseconds: Self.requestTimeoutNanoseconds
        )
        scheduleIdleShutdownIfQuiet()
        return response
    }

    func getAuthStatus(refreshToken: Bool = false) async throws -> AuthStatus {
        try await connect()
        let response: GetAuthStatusResponseDTO = try await requireTransport().request(
            "getAuthStatus",
            params: GetAuthStatusParams(includeToken: false, refreshToken: refreshToken),
            response: GetAuthStatusResponseDTO.self,
            timeoutNanoseconds: Self.requestTimeoutNanoseconds
        )
        scheduleIdleShutdownIfQuiet()
        return response.status
    }

    func localLoginStatus() async -> AuthStatus? {
        await CodexLoginStatusProbe.readStatus(binaryURL: binaryURL)
    }

    func startChatGPTLogin() async throws -> LoginAccountResponseDTO {
        try await connect()
        let response: LoginAccountResponseDTO = try await requireTransport().request(
            "account/login/start",
            params: LoginAccountParams.chatGPT,
            response: LoginAccountResponseDTO.self,
            timeoutNanoseconds: Self.mutationTimeoutNanoseconds
        )
        if let loginID = response.loginId {
            pendingLoginIDs.insert(loginID)
        }
        scheduleIdleShutdownIfQuiet()
        return response
    }

    func respondToApproval(_ approval: ApprovalRequest, decision: ApprovalDecision) async throws {
        try await connect()
        pendingApprovalIDs.remove(approval.requestID)

        switch approval.kind {
        case .commandExecution:
            try await requireTransport().respond(to: approval.requestID, result: ["decision": decision.rawValue])
        case .fileChange:
            try await requireTransport().respond(to: approval.requestID, result: ["decision": decision.rawValue])
        case .permissions:
            try await requireTransport().respond(to: approval.requestID, result: ["decision": decision.rawValue])
        case .unknown:
            try await requireTransport().respond(to: approval.requestID, result: ["decision": decision.rawValue])
        }

        scheduleIdleShutdownIfQuiet()
    }

    private func requireTransport() throws -> LineJSONRPCTransport {
        guard let transport else { throw CodexClientError.notConnected }
        return transport
    }

    private func startEventPump(_ transport: LineJSONRPCTransport) {
        eventPump?.cancel()
        eventPump = Task { [weak self] in
            for await event in transport.events {
                await self?.handleTransportEvent(event)
            }
        }
    }

    private func handleTransportEvent(_ event: CodexTransportEvent) async {
        switch event {
        case .notification(let method, let params):
            handleNotification(method: method, params: params)
        case .serverRequest(let request):
            let approval = ApprovalRequest.from(request)
            pendingApprovalIDs.insert(request.id)
            eventContinuation.yield(.approvalRequested(approval))
        case .unknown(let message):
            eventContinuation.yield(.unknown(method: message.method, params: message.params))
        case .terminated(let code):
            initialized = false
            transport = nil
            eventContinuation.yield(.terminated(code))
        }
    }

    private func handleNotification(method: String, params: JSONValue?) {
        switch method {
        case "thread/started":
            if let thread = try? params?["thread"]?.decode(ThreadDTO.self) {
                eventContinuation.yield(.threadStarted(thread.summary))
            } else {
                eventContinuation.yield(.notification(method: method, params: params))
            }

        case "thread/status/changed":
            let threadID = params?["threadId"]?.stringValue ?? ""
            let status = params?["status"]?.stringValue ?? params?["status"]?.debugSummary ?? "unknown"
            eventContinuation.yield(.threadStatusChanged(threadID: threadID, status: status))

        case "turn/started":
            if let threadID = params?["threadId"]?.stringValue,
               let turn = try? params?["turn"]?.decode(TurnDTO.self) {
                activeTurnIDs.insert(turn.id)
                eventContinuation.yield(.turnStarted(threadID: threadID, turn: turn.model))
            }

        case "turn/completed":
            if let threadID = params?["threadId"]?.stringValue,
               let turn = try? params?["turn"]?.decode(TurnDTO.self) {
                activeTurnIDs.remove(turn.id)
                eventContinuation.yield(.turnCompleted(threadID: threadID, turn: turn.model))
                scheduleIdleShutdownIfQuiet()
            }

        case "item/started", "item/completed":
            if let threadID = params?["threadId"]?.stringValue,
               let turnID = params?["turnId"]?.stringValue,
               let item = params?["item"] {
                eventContinuation.yield(.itemUpdated(threadID: threadID, turnID: turnID, item: TranscriptItem.fromThreadItem(item)))
            }

        case "item/agentMessage/delta":
            if let threadID = params?["threadId"]?.stringValue,
               let turnID = params?["turnId"]?.stringValue,
               let itemID = params?["itemId"]?.stringValue,
               let delta = params?["delta"]?.stringValue {
                eventContinuation.yield(.assistantDelta(threadID: threadID, turnID: turnID, itemID: itemID, delta: delta))
            }

        case "item/commandExecution/outputDelta":
            if let threadID = params?["threadId"]?.stringValue,
               let turnID = params?["turnId"]?.stringValue,
               let itemID = params?["itemId"]?.stringValue,
               let delta = params?["delta"]?.stringValue {
                eventContinuation.yield(.commandOutputDelta(threadID: threadID, turnID: turnID, itemID: itemID, delta: delta))
            }

        case "turn/diff/updated":
            if let threadID = params?["threadId"]?.stringValue,
               let turnID = params?["turnId"]?.stringValue,
               let diff = params?["diff"]?.stringValue {
                eventContinuation.yield(.diffUpdated(DiffSnapshot(threadID: threadID, turnID: turnID, unifiedDiff: diff)))
            }

        case "error":
            if let threadID = params?["threadId"]?.stringValue {
                let turnID = params?["turnId"]?.stringValue
                let message = params?["error"]?["message"]?.stringValue ?? params?.debugSummary ?? "Codex hatasi"
                eventContinuation.yield(.turnError(threadID: threadID, turnID: turnID, message: message))
            } else {
                eventContinuation.yield(.notification(method: method, params: params))
            }

        case "account/updated":
            eventContinuation.yield(.accountUpdated)

        case "account/login/completed":
            let loginID = params?["loginId"]?.stringValue
            if let loginID {
                pendingLoginIDs.remove(loginID)
            }
            let success = params?["success"]?.boolValue ?? false
            let error = params?["error"]?.stringValue
            eventContinuation.yield(.accountLoginCompleted(loginID: loginID, success: success, error: error))
            scheduleIdleShutdownIfQuiet()

        default:
            logger.debug("unknown notification: \(method, privacy: .public)")
            eventContinuation.yield(.notification(method: method, params: params))
        }
    }

    private func scheduleIdleShutdownIfQuiet() {
        guard activeTurnIDs.isEmpty, pendingApprovalIDs.isEmpty, pendingLoginIDs.isEmpty else { return }
        idleTask?.cancel()
        idleTask = Task { [weak self, idleShutdownNanoseconds] in
            try? await Task.sleep(nanoseconds: idleShutdownNanoseconds)
            await self?.disconnectIfStillQuiet()
        }
    }

    private func disconnectIfStillQuiet() async {
        guard activeTurnIDs.isEmpty, pendingApprovalIDs.isEmpty, pendingLoginIDs.isEmpty else { return }
        await disconnect()
    }
}

extension ApprovalRequest {
    static func from(_ envelope: ServerRequestEnvelope) -> ApprovalRequest {
        let params = envelope.params
        let threadID = params?["threadId"]?.stringValue
        let turnID = params?["turnId"]?.stringValue
        let itemID = params?["itemId"]?.stringValue
        let cwd = params?["cwd"]?.stringValue
        let reason = params?["reason"]?.stringValue

        switch envelope.method {
        case "item/commandExecution/requestApproval", "execCommandApproval":
            let command = params?["command"]?.stringValue ?? "Komut onayi"
            return ApprovalRequest(
                requestID: envelope.id,
                kind: .commandExecution,
                method: envelope.method,
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                title: command,
                detail: reason ?? command,
                cwd: cwd
            )

        case "item/fileChange/requestApproval", "applyPatchApproval":
            let grantRoot = params?["grantRoot"]?.stringValue
            return ApprovalRequest(
                requestID: envelope.id,
                kind: .fileChange,
                method: envelope.method,
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                title: "Dosya degisikligi onayi",
                detail: reason ?? grantRoot ?? "Codex dosya sistemi izni istiyor.",
                cwd: cwd
            )

        case "item/permissions/requestApproval":
            return ApprovalRequest(
                requestID: envelope.id,
                kind: .permissions,
                method: envelope.method,
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                title: "Izin onayi",
                detail: reason ?? params?.debugSummary ?? "",
                cwd: cwd
            )

        default:
            return ApprovalRequest(
                requestID: envelope.id,
                kind: .unknown,
                method: envelope.method,
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                title: envelope.method,
                detail: params?.debugSummary ?? "",
                cwd: cwd
            )
        }
    }
}

enum CodexLoginStatusProbe {
    static func readStatus(binaryURL: URL) async -> AuthStatus? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = binaryURL
            process.arguments = ["login", "status"]
            process.environment = ProcessEnvironment.withCommonPaths()

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
                let processBox = SendableProcess(process)
                let watchdog = Task {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if processBox.process.isRunning {
                        processBox.process.terminate()
                    }
                }
                process.waitUntilExit()
                watchdog.cancel()
            } catch {
                return nil
            }

            let output = [
                stdout.fileHandleForReading.readDataToEndOfFile(),
                stderr.fileHandleForReading.readDataToEndOfFile()
            ]
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")

            return parseStatus(output)
        }.value
    }

    private static func parseStatus(_ output: String) -> AuthStatus? {
        let lowercased = output.lowercased()
        if let range = lowercased.range(of: "logged in using ") {
            let methodStart = range.upperBound
            let method = output[methodStart...]
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .signedIn(method: normalizedMethod(method))
        }

        if lowercased.contains("not logged in") || lowercased.contains("not currently logged in") {
            return .signedOut
        }

        return nil
    }

    private static func normalizedMethod(_ method: String?) -> String {
        guard let method, !method.isEmpty else { return "codex" }
        if method.localizedCaseInsensitiveContains("chatgpt") {
            return "chatgpt"
        }
        if method.localizedCaseInsensitiveContains("api") {
            return "apikey"
        }
        return method.lowercased()
    }
}

private struct SendableProcess: @unchecked Sendable {
    let process: Process

    init(_ process: Process) {
        self.process = process
    }
}
