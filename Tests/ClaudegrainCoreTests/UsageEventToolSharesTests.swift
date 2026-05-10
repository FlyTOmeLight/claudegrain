import XCTest
@testable import ClaudegrainCore

final class UsageEventToolSharesTests: XCTestCase {

    private func event(tools: [String]) -> UsageEvent {
        UsageEvent(
            timestamp: Date(),
            sessionId: "s",
            cwd: nil,
            gitBranch: nil,
            model: "claude-sonnet-4-6",
            tools: tools,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0
        )
    }

    func testNoToolsReturnsNil() {
        XCTAssertNil(event(tools: []).toolShares)
    }

    func testSingleToolGetsFullShare() throws {
        let s = try XCTUnwrap(event(tools: ["Read"]).toolShares)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(try XCTUnwrap(s["Read"]), 1.0, accuracy: 1e-9)
    }

    func testTwoDistinctToolsHalfHalf() throws {
        let s = try XCTUnwrap(event(tools: ["Read", "Bash"]).toolShares)
        XCTAssertEqual(try XCTUnwrap(s["Read"]), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s["Bash"]), 0.5, accuracy: 1e-9)
    }

    func testRepeatedToolDedupedByCount() throws {
        // Per ADR-0015: shares aggregate by name. [Read, Read, Bash] ⇒ 2/3 + 1/3.
        let s = try XCTUnwrap(event(tools: ["Read", "Read", "Bash"]).toolShares)
        XCTAssertEqual(try XCTUnwrap(s["Read"]), 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s["Bash"]), 1.0 / 3.0, accuracy: 1e-9)
    }

    func testThreeDistinctToolsThirds() throws {
        let s = try XCTUnwrap(event(tools: ["Read", "Bash", "Edit"]).toolShares)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(try XCTUnwrap(s["Read"]), 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s["Bash"]), 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s["Edit"]), 1.0 / 3.0, accuracy: 1e-9)
    }

    func testSharesAlwaysSumToOne() {
        for tools in [["Read"], ["a", "b"], ["a", "a", "b"], ["a", "b", "c", "d"]] {
            let s = event(tools: tools).toolShares!
            let total = s.values.reduce(0, +)
            XCTAssertEqual(total, 1.0, accuracy: 1e-9, "shares for \(tools) summed to \(total)")
        }
    }

    func testPrimaryToolUnchangedFromV1() {
        // ADR-0015 keeps primaryTool = tools.first for backward compat.
        XCTAssertEqual(event(tools: ["Read", "Bash"]).primaryTool, "Read")
        XCTAssertNil(event(tools: []).primaryTool)
    }
}
