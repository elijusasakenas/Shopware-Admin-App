//
//  AIProviderResponseNormalizer.swift
//  ShopwareApp
//
//  Converts OpenAI Responses and Gemini Interactions output into the app's
//  provider-neutral conversation blocks. The approval gateway deliberately
//  receives the same mcp_tool_use shape it already validates for Anthropic.
//

import Foundation

struct AIProviderResult {
    let content: [AIContentBlock]
    let stopReason: String?
    let usage: AIChatResponse.Usage?
}

enum AIProviderResponseNormalizer {
    static func openAI(_ raw: JSONValue) -> AIProviderResult {
        var content: [AIContentBlock] = []
        var seenText = Set<String>()

        func addText(_ text: String?) {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty, seenText.insert(trimmed).inserted else { return }
            content.append(.text(trimmed))
        }

        addText(raw["output_text"]?.stringValue)
        for item in raw["output"]?.arrayValue ?? [] {
            let type = item["type"]?.stringValue ?? ""
            if type == "message" {
                for part in item["content"]?.arrayValue ?? [] {
                    if ["output_text", "text"].contains(part["type"]?.stringValue ?? "") {
                        addText(part["text"]?.stringValue)
                    }
                }
            } else if type == "mcp_call" {
                appendMCPCall(item, to: &content)
            }
        }

        let usage = makeUsage(
            input: raw["usage"]?["input_tokens"]?.intValue,
            output: raw["usage"]?["output_tokens"]?.intValue
        )
        let incompleteReason = raw["incomplete_details"]?["reason"]?.stringValue
        let stopReason = incompleteReason == "max_output_tokens" ? "max_tokens" : "end_turn"
        return AIProviderResult(content: content, stopReason: stopReason, usage: usage)
    }

    static func gemini(_ raw: JSONValue) -> AIProviderResult {
        var content: [AIContentBlock] = []
        var seenText = Set<String>()

        func addText(_ text: String?) {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty, seenText.insert(trimmed).inserted else { return }
            content.append(.text(trimmed))
        }

        addText(raw["output_text"]?.stringValue)
        addText(raw["outputText"]?.stringValue)
        for step in raw["steps"]?.arrayValue ?? [] {
            let type = (step["type"]?.stringValue ?? "").lowercased()
            if type.contains("model") || type.contains("message") || type.contains("text") {
                addText(step["text"]?.stringValue)
                addText(step["output_text"]?.stringValue)
                addText(step["outputText"]?.stringValue)
                for part in step["content"]?.arrayValue ?? [] {
                    addText(part["text"]?.stringValue)
                }
            }
            if type.contains("result") && (type.contains("mcp") || type.contains("tool")) {
                appendMCPResult(step, to: &content)
            } else if type.contains("mcp") || type.contains("tool_call") {
                appendMCPCall(step, to: &content)
            }
        }

        let usageObject = raw["usage"] ?? raw["usage_metadata"] ?? raw["usageMetadata"]
        let usage = makeUsage(
            input: firstInt(in: usageObject, keys: ["total_input_tokens", "input_tokens", "inputTokenCount", "promptTokenCount"]),
            output: firstInt(in: usageObject, keys: ["total_output_tokens", "output_tokens", "outputTokenCount", "candidatesTokenCount"])
        )
        return AIProviderResult(content: content, stopReason: "end_turn", usage: usage)
    }

    private static func appendMCPCall(_ item: JSONValue, to content: inout [AIContentBlock]) {
        guard let name = item["name"]?.stringValue ?? item["tool_name"]?.stringValue else { return }
        let id = item["id"]?.stringValue ?? item["call_id"]?.stringValue ?? UUID().uuidString
        let parsedArguments: JSONValue?
        if let rawArguments = item["arguments"] {
            parsedArguments = parseArguments(rawArguments)
        } else {
            parsedArguments = nil
        }
        let arguments = parsedArguments ?? item["input"] ?? item["args"] ?? .object([:])
        content.append(.other(.object([
            "type": .string("mcp_tool_use"),
            "id": .string(id),
            "name": .string(name),
            "input": arguments
        ])))

        let error = item["error"]
        let output = item["output"] ?? item["result"] ?? error
        guard let output, output != .null else { return }
        content.append(.other(.object([
            "type": .string("mcp_tool_result"),
            "tool_use_id": .string(id),
            "content": .string(stringify(output)),
            "is_error": .bool(error != nil && error != .null)
        ])))
    }

    private static func appendMCPResult(_ item: JSONValue, to content: inout [AIContentBlock]) {
        guard let id = item["call_id"]?.stringValue ?? item["id"]?.stringValue else { return }
        let result = item["result"] ?? item["output"] ?? item["error"] ?? .null
        content.append(.other(.object([
            "type": .string("mcp_tool_result"),
            "tool_use_id": .string(id),
            "content": .string(stringify(result)),
            "is_error": .bool(item["is_error"]?.boolValue == true || (item["error"] != nil && item["error"] != .null))
        ])))
    }

    private static func parseArguments(_ value: JSONValue) -> JSONValue? {
        guard let string = value.stringValue else { return value }
        return try? JSONDecoder().decode(JSONValue.self, from: Data(string.utf8))
    }

    private static func stringify(_ value: JSONValue) -> String {
        if let string = value.stringValue { return string }
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func firstInt(in value: JSONValue?, keys: [String]) -> Int? {
        for key in keys {
            if let result = value?[key]?.intValue { return result }
        }
        return nil
    }

    private static func makeUsage(input: Int?, output: Int?) -> AIChatResponse.Usage? {
        guard input != nil || output != nil else { return nil }
        return AIChatResponse.Usage(
            inputTokens: input,
            outputTokens: output,
            cacheCreationInputTokens: nil,
            cacheReadInputTokens: nil
        )
    }
}
