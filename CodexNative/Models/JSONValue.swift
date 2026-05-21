import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { value } else { nil }
    }

    var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }

    var intValue: Int? {
        if case .number(let value) = self { Int(value) } else { nil }
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    func decode<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        let data = try JSONEncoder.codex.encode(self)
        return try decoder.decode(type, from: data)
    }

    static func encoded<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder.codex.encode(value)
        return try JSONDecoder.codex.decode(JSONValue.self, from: data)
    }
}

extension JSONEncoder {
    static var codex: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var codex: JSONDecoder {
        JSONDecoder()
    }
}

enum RPCID: Codable, Hashable, Sendable, CustomStringConvertible {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        }
    }

    var description: String {
        switch self {
        case .string(let value):
            value
        case .int(let value):
            String(value)
        }
    }
}

struct JSONRPCErrorObject: Codable, Error, Equatable, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?
}

struct JSONRPCIncomingMessage: Decodable, Sendable {
    let id: RPCID?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: JSONRPCErrorObject?
}

struct JSONRPCOutgoingRequest: Encodable, Sendable {
    let id: RPCID
    let method: String
    let params: JSONValue?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(params, forKey: .params)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case method
        case params
    }
}

struct JSONRPCOutgoingNotification: Encodable, Sendable {
    let method: String
}

struct JSONRPCOutgoingResponse: Encodable, Sendable {
    let id: RPCID
    let result: JSONValue
}

struct JSONLineFramer: Sendable {
    private var buffer = Data()

    mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            if !line.isEmpty {
                lines.append(Data(line))
            }
            buffer.removeSubrange(...newline)
        }

        return lines
    }

    mutating func flush() -> Data? {
        guard !buffer.isEmpty else { return nil }
        defer { buffer.removeAll(keepingCapacity: true) }
        return buffer
    }
}
