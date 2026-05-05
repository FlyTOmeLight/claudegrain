import XCTest
@testable import ClaudegrainCore

final class JSONLParserTests: XCTestCase {
    func testParsesMcpToolUseAssistantEvent() throws {
        let json: [String: Any] = [
            "type": "assistant",
            "timestamp": "2026-04-20T19:28:50.358Z",
            "sessionId": "c5ba651b-7693-4e91-a7b2-cacbd3d5e7e0",
            "cwd": "/Users/moonlight/new/prism-endpoint",
            "gitBranch": "zbh-patch",
            "message": [
                "model": "claude-opus-4-7",
                "content": [
                    [
                        "type": "tool_use",
                        "name": "mcp__plugin_claude-mem_mcp-search__get_observations",
                    ] as [String: Any],
                ],
                "usage": [
                    "input_tokens": 6,
                    "cache_creation_input_tokens": 34100,
                    "cache_read_input_tokens": 17220,
                    "output_tokens": 92,
                ] as [String: Any],
            ] as [String: Any],
        ]

        let parser = JSONLParser()
        let event = try XCTUnwrap(parser.parse(raw: json))

        XCTAssertEqual(event.model, "claude-opus-4-7")
        XCTAssertEqual(event.inputTokens, 6)
        XCTAssertEqual(event.outputTokens, 92)
        XCTAssertEqual(event.cacheCreationTokens, 34100)
        XCTAssertEqual(event.cacheReadTokens, 17220)
        XCTAssertEqual(event.cwd, "/Users/moonlight/new/prism-endpoint")
        XCTAssertEqual(event.tools, ["mcp__plugin_claude-mem_mcp-search__get_observations"])
        XCTAssertEqual(event.modelFamily, .opus)
    }

    func testIgnoresUserAndSystemEvents() {
        let json: [String: Any] = ["type": "user", "message": ["content": "hi"]]
        XCTAssertNil(JSONLParser().parse(raw: json))
    }

    func testIgnoresSyntheticModel() {
        let json: [String: Any] = [
            "type": "assistant",
            "timestamp": "2026-05-04T12:00:00Z",
            "sessionId": "s",
            "message": [
                "model": "<synthetic>",
                "content": [],
                "usage": ["input_tokens": 0, "output_tokens": 0],
            ] as [String: Any],
        ]
        XCTAssertNil(JSONLParser().parse(raw: json))
    }

    func testMcpComponentsSplit() {
        let result = "mcp__plugin_claude-mem_mcp-search__get_observations".mcpComponents()
        XCTAssertEqual(result?.server, "plugin_claude-mem_mcp-search")
        XCTAssertEqual(result?.tool, "get_observations")

        XCTAssertNil("Bash".mcpComponents())
    }

    func testPrimaryToolPicksFirstToolUse() {
        let event = UsageEvent(
            timestamp: Date(),
            sessionId: "s",
            cwd: nil,
            gitBranch: nil,
            model: "claude-sonnet-4-6",
            tools: ["Bash", "mcp__exa__search", "Edit"],
            inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0
        )
        XCTAssertEqual(event.primaryTool, "Bash")
        XCTAssertNil(event.primaryMcpServer)
    }

    func testPrimaryMcpServerExtracted() {
        let event = UsageEvent(
            timestamp: Date(),
            sessionId: "s",
            cwd: nil,
            gitBranch: nil,
            model: "claude-opus-4-7",
            tools: ["mcp__plugin_context7__query-docs", "Bash"],
            inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0
        )
        XCTAssertEqual(event.primaryTool, "mcp__plugin_context7__query-docs")
        XCTAssertEqual(event.primaryMcpServer, "plugin_context7")
    }

    func testPrimaryToolNilForTextOnlyTurn() {
        let event = UsageEvent(
            timestamp: Date(),
            sessionId: "s",
            cwd: nil,
            gitBranch: nil,
            model: "claude-sonnet-4-6",
            tools: [],
            inputTokens: 100, outputTokens: 200, cacheCreationTokens: 0, cacheReadTokens: 0
        )
        XCTAssertNil(event.primaryTool)
    }

    func testJSONLReaderResetsOnTruncation() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("claudegrain-test-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("line1\nline2\n".utf8).write(to: tmp)
        let reader = JSONLReader()
        let (lines1, cursor1) = try reader.readNew(at: tmp, from: .init())
        XCTAssertEqual(lines1.count, 2)
        XCTAssertGreaterThan(cursor1.offset, 0)

        // Truncate file to a smaller size — simulates rotation.
        try Data("only-line\n".utf8).write(to: tmp)
        let (lines2, cursor2) = try reader.readNew(at: tmp, from: cursor1)
        XCTAssertEqual(lines2.count, 1)
        XCTAssertEqual(String(data: lines2[0], encoding: .utf8), "only-line")
        XCTAssertEqual(cursor2.offset, UInt64("only-line\n".utf8.count))
    }

    func testJSONLReaderIncrementalAppend() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("claudegrain-test-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("a\n".utf8).write(to: tmp)
        let reader = JSONLReader()
        let (_, cursor1) = try reader.readNew(at: tmp, from: .init())

        let handle = try FileHandle(forWritingTo: tmp)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("b\nc\n".utf8))
        try handle.close()

        let (lines2, _) = try reader.readNew(at: tmp, from: cursor1)
        XCTAssertEqual(lines2.map { String(data: $0, encoding: .utf8) }, ["b", "c"])
    }

    func testCostCalculatorOpus() {
        let event = UsageEvent(
            timestamp: Date(),
            sessionId: "s",
            cwd: nil,
            gitBranch: nil,
            model: "claude-opus-4-7",
            tools: [],
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheCreationTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(CostCalculator.cost(for: event), 90.0, accuracy: 0.001)
    }
}
