//
//  AIChatModels.swift
//  ShopwareApp
//
//  Wire types for the AI chat proxy (Anthropic Messages API shapes) and the
//  chat transcript entries the UI renders.
//

import Foundation

// MARK: - Flexible JSON

/// A JSON value that round-trips unchanged, used for tool inputs/schemas
/// whose shape is decided by the model at runtime.
enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

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
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    // Convenience readers for tool input fields.
    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    var intValue: Int? { doubleValue.map { Int($0) } }
}

// MARK: - Messages API shapes

/// One content block inside a message. Unknown block types are carried
/// through verbatim so the conversation can be replayed to the API unchanged.
enum AIContentBlock: Codable, Equatable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String, content: String, isError: Bool)
    case other(JSONValue)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "tool_use":
            self = .toolUse(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                input: try container.decode(JSONValue.self, forKey: .input)
            )
        case "tool_result":
            self = .toolResult(
                toolUseID: try container.decode(String.self, forKey: .toolUseID),
                content: (try? container.decode(String.self, forKey: .content)) ?? "",
                isError: (try? container.decode(Bool.self, forKey: .isError)) ?? false
            )
        default:
            self = .other(try JSONValue(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseID, let content, let isError):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
            if isError { try container.encode(true, forKey: .isError) }
        case .other(let raw):
            try raw.encode(to: encoder)
        }
    }
}

struct AIMessage: Codable, Equatable {
    let role: String
    let content: [AIContentBlock]

    static func user(_ text: String) -> AIMessage {
        AIMessage(role: "user", content: [.text(text)])
    }
}

struct AIChatResponse: Decodable {
    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    let content: [AIContentBlock]
    let stopReason: String?
    let usage: Usage?

    private enum CodingKeys: String, CodingKey {
        case content, usage
        case stopReason = "stop_reason"
    }
}

// MARK: - Transcript entries (UI)

/// One rendered row in the chat transcript.
struct ChatEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case user(String)
        case assistant(String)
        /// A tool the assistant ran, shown as a small activity chip.
        case toolActivity(label: String, failed: Bool)
        case error(String)
    }

    let id = UUID()
    let kind: Kind
}
