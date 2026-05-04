import Foundation

public struct JSONLParser: Sendable {
    public init() {}

    /// Parse a single JSONL line. Returns nil for non-assistant or malformed entries.
    public func parse(line: Data) -> UsageEvent? {
        guard let raw = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return nil
        }
        return parse(raw: raw)
    }

    public func parse(raw: [String: Any]) -> UsageEvent? {
        guard (raw["type"] as? String) == "assistant" else { return nil }
        guard let message = raw["message"] as? [String: Any] else { return nil }
        guard let usage = message["usage"] as? [String: Any] else { return nil }

        let model = message["model"] as? String ?? "unknown"
        // Synthetic events (e.g. tool-call placeholders inserted by Claude Code) carry
        // no real cost. Skip them to avoid polluting aggregations.
        if model.hasPrefix("<") { return nil }
        let inputTokens = usage["input_tokens"] as? Int ?? 0
        let outputTokens = usage["output_tokens"] as? Int ?? 0
        let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

        let tools: [String] = {
            guard let content = message["content"] as? [[String: Any]] else { return [] }
            return content.compactMap { block in
                (block["type"] as? String) == "tool_use" ? (block["name"] as? String) : nil
            }
        }()

        let timestamp = Self.parseISO8601(raw["timestamp"] as? String) ?? Date()
        let sessionId = raw["sessionId"] as? String ?? ""
        let cwd = raw["cwd"] as? String
        let gitBranch = raw["gitBranch"] as? String
        let messageId = message["id"] as? String
        let requestId = raw["requestId"] as? String

        return UsageEvent(
            timestamp: timestamp,
            sessionId: sessionId,
            cwd: cwd,
            gitBranch: gitBranch,
            model: model,
            tools: tools,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreate,
            cacheReadTokens: cacheRead,
            messageId: messageId,
            requestId: requestId
        )
    }

    static func parseISO8601(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public extension String {
    /// Splits an MCP tool name `mcp__<server>__<tool>` into `(server, tool)`.
    /// Returns nil for non-MCP tools.
    func mcpComponents() -> (server: String, tool: String)? {
        guard hasPrefix("mcp__") else { return nil }
        let stripped = String(dropFirst(5))
        guard let separator = stripped.range(of: "__") else { return nil }
        let server = String(stripped[..<separator.lowerBound])
        let tool = String(stripped[separator.upperBound...])
        return (server, tool)
    }
}
