import Foundation
import OSLog

enum CodexTransportError: LocalizedError, Sendable {
    case processNotStarted
    case processExited(Int32)
    case malformedMessage(String)
    case rpc(JSONRPCErrorObject)
    case missingResult(RPCID)

    var errorDescription: String? {
        switch self {
        case .processNotStarted:
            "Codex app-server calismiyor."
        case .processExited(let code):
            "Codex app-server kapandi. Cikis kodu: \(code)."
        case .malformedMessage(let line):
            "Gecersiz JSON-RPC mesaji: \(line)"
        case .rpc(let error):
            "Codex RPC hatasi \(error.code): \(error.message)"
        case .missingResult(let id):
            "RPC yaniti sonuc icermiyor: \(id)"
        }
    }
}

struct ServerRequestEnvelope: Sendable, Identifiable {
    let id: RPCID
    let method: String
    let params: JSONValue?

    var identity: String { id.description }
}

enum CodexTransportEvent: Sendable {
    case notification(method: String, params: JSONValue?)
    case serverRequest(ServerRequestEnvelope)
    case unknown(JSONRPCIncomingMessage)
    case terminated(Int32)
}

protocol CodexTransport: Sendable {
    var events: AsyncStream<CodexTransportEvent> { get }

    func start() async throws
    func stop() async
    func request<Response: Decodable & Sendable>(_ method: String, response: Response.Type) async throws -> Response
    func request<Params: Encodable & Sendable, Response: Decodable & Sendable>(
        _ method: String,
        params: Params,
        response: Response.Type
    ) async throws -> Response
    func respond<Result: Encodable & Sendable>(to id: RPCID, result: Result) async throws
}

actor LineJSONRPCTransport: CodexTransport {
    nonisolated let events: AsyncStream<CodexTransportEvent>

    private let binaryURL: URL
    private let logger = Logger(subsystem: "CodexNative", category: "JSONRPC")
    private let continuation: AsyncStream<CodexTransportEvent>.Continuation
    private var process: Process?
    private var input: SendableFileHandle?
    private var readTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var nextID = 1
    private var pending: [RPCID: CheckedContinuation<JSONValue, Error>] = [:]

    init(binaryURL: URL) {
        self.binaryURL = binaryURL
        var localContinuation: AsyncStream<CodexTransportEvent>.Continuation?
        self.events = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation!
    }

    func start() async throws {
        guard process == nil else { return }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["app-server", "--listen", "stdio://"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        self.process = process
        self.input = SendableFileHandle(stdinPipe.fileHandleForWriting)

        let stdout = SendableFileHandle(stdoutPipe.fileHandleForReading)
        readTask = Task { [weak self] in
            await self?.readLoop(stdout)
        }

        let stderr = SendableFileHandle(stderrPipe.fileHandleForReading)
        stderrTask = Task { [weak self] in
            await self?.stderrLoop(stderr)
        }
    }

    func stop() async {
        readTask?.cancel()
        stderrTask?.cancel()
        readTask = nil
        stderrTask = nil

        for (_, pending) in pending {
            pending.resume(throwing: CodexTransportError.processNotStarted)
        }
        pending.removeAll()

        input?.close()
        input = nil

        if let process, process.isRunning {
            process.terminate()
        }
        let code = process?.terminationStatus ?? 0
        process = nil
        continuation.yield(.terminated(code))
    }

    func request<Response: Decodable & Sendable>(_ method: String, response: Response.Type) async throws -> Response {
        try await request(method, params: Optional<EmptyParams>.none, response: response)
    }

    func request<Params: Encodable & Sendable, Response: Decodable & Sendable>(
        _ method: String,
        params: Params,
        response: Response.Type
    ) async throws -> Response {
        try await request(method, params: Optional(params), response: response)
    }

    private func request<Params: Encodable & Sendable, Response: Decodable & Sendable>(
        _ method: String,
        params: Params?,
        response: Response.Type
    ) async throws -> Response {
        let id = RPCID.int(nextID)
        nextID += 1

        let paramsValue = try params.map(JSONValue.encoded)
        let request = JSONRPCOutgoingRequest(id: id, method: method, params: paramsValue)

        let result = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try write(request)
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }

        guard !(result == .null && Response.self != EmptyResponse.self) else {
            throw CodexTransportError.missingResult(id)
        }

        return try result.decode(Response.self)
    }

    func respond<Result: Encodable & Sendable>(to id: RPCID, result: Result) async throws {
        let value = try JSONValue.encoded(result)
        try write(JSONRPCOutgoingResponse(id: id, result: value))
    }

    private func write<T: Encodable & Sendable>(_ envelope: T) throws {
        guard let input else { throw CodexTransportError.processNotStarted }
        var data = try JSONEncoder.codex.encode(envelope)
        data.append(0x0A)
        try input.write(data)
    }

    private func readLoop(_ stdout: SendableFileHandle) async {
        var framer = JSONLineFramer()
        do {
            for try await chunk in stdout.bytes {
                let lines = framer.append(Data([chunk]))
                for line in lines {
                    await handleLine(line)
                }
            }

            if let tail = framer.flush() {
                await handleLine(tail)
            }
        } catch {
            logger.error("stdout read failed: \(error.localizedDescription, privacy: .public)")
        }

        let code = process?.terminationStatus ?? 0
        continuation.yield(.terminated(code))
    }

    private func stderrLoop(_ stderr: SendableFileHandle) async {
        do {
            for try await line in stderr.bytes.lines {
                logger.debug("app-server stderr: \(line, privacy: .public)")
            }
        } catch {
            logger.debug("stderr read finished: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleLine(_ data: Data) async {
        guard let line = String(data: data, encoding: .utf8) else {
            continuation.yield(.unknown(JSONRPCIncomingMessage(id: nil, method: nil, params: nil, result: nil, error: nil)))
            return
        }

        do {
            let message = try JSONDecoder.codex.decode(JSONRPCIncomingMessage.self, from: data)

            if let id = message.id, let error = message.error {
                pending.removeValue(forKey: id)?.resume(throwing: CodexTransportError.rpc(error))
                return
            }

            if let id = message.id, message.result != nil {
                pending.removeValue(forKey: id)?.resume(returning: message.result ?? .null)
                return
            }

            if let id = message.id, let method = message.method {
                continuation.yield(.serverRequest(ServerRequestEnvelope(id: id, method: method, params: message.params)))
                return
            }

            if let method = message.method {
                continuation.yield(.notification(method: method, params: message.params))
                return
            }

            continuation.yield(.unknown(message))
        } catch {
            logger.error("failed to decode JSON-RPC line: \(line, privacy: .public)")
            continuation.yield(.unknown(JSONRPCIncomingMessage(id: nil, method: nil, params: .string(line), result: nil, error: nil)))
        }
    }
}

struct EmptyParams: Codable, Sendable {}
struct EmptyResponse: Codable, Sendable {}

private struct SendableFileHandle: @unchecked Sendable {
    let handle: FileHandle

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    var bytes: FileHandle.AsyncBytes {
        handle.bytes
    }

    func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
    }

    func close() {
        try? handle.close()
    }
}
