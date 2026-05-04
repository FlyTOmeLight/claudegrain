import XCTest
@testable import ClaudegrainCore

final class IngestActorTests: XCTestCase {
    private var dbURL: URL!
    private var projectsRoot: URL!

    override func setUp() async throws {
        let id = UUID().uuidString
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudegrain-ingest-\(id).db")
        projectsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudegrain-projects-\(id)")
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.removeItem(at: projectsRoot)
    }

    func testBootstrapConsumesIncrementalAppends() async throws {
        let projDir = projectsRoot.appendingPathComponent("project-a")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        let jsonl = projDir.appendingPathComponent("session.jsonl")
        try makeAssistantLine(model: "claude-sonnet-4-6", tool: "Bash", inTok: 100, outTok: 200, cwd: "/Users/me/repo-x").write(to: jsonl)

        let db = try EventsDatabase(url: dbURL)
        let actor = IngestActor(db: db, projectsRoot: projectsRoot)
        try await actor.bootstrap(daysBack: 7)

        var totals = try await db.dailyTotals(on: Date())
        XCTAssertEqual(totals.totalTokens, 300)
        let canonical = jsonl.resolvingSymlinksInPath().path
        let cursor1 = try await db.cursor(for: canonical)
        XCTAssertGreaterThan(cursor1.offset, 0)

        // Append a second line — bootstrap again should only ingest the delta.
        let handle = try FileHandle(forWritingTo: jsonl)
        try handle.seekToEnd()
        try handle.write(contentsOf: makeAssistantLine(model: "claude-haiku-4-5", tool: "Edit", inTok: 50, outTok: 50, cwd: "/Users/me/repo-x"))
        try handle.close()

        try await actor.bootstrap(daysBack: 7)
        totals = try await db.dailyTotals(on: Date())
        XCTAssertEqual(totals.totalTokens, 400)

        let cursor2 = try await db.cursor(for: canonical)
        XCTAssertGreaterThan(cursor2.offset, cursor1.offset)
    }

    private func makeAssistantLine(model: String, tool: String, inTok: Int, outTok: Int, cwd: String) -> Data {
        let payload: [String: Any] = [
            "type": "assistant",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "sessionId": UUID().uuidString,
            "cwd": cwd,
            "message": [
                "model": model,
                "content": [["type": "tool_use", "name": tool] as [String: Any]],
                "usage": ["input_tokens": inTok, "output_tokens": outTok] as [String: Any],
            ] as [String: Any],
        ]
        var data = try! JSONSerialization.data(withJSONObject: payload)
        data.append(Data([0x0A]))
        return data
    }
}
