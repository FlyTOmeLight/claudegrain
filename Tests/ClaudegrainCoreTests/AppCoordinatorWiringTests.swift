import XCTest
@testable import ClaudegrainCore
@testable import ClaudegrainApp

@MainActor
final class AppCoordinatorWiringTests: XCTestCase {
    func testRefreshPopulatesForecastAndWeekDeltaAndModelMix() async throws {
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-coord-\(UUID().uuidString).db")
        let db = try EventsDatabase(url: dbURL)
        let now = Date()
        let event = UsageEvent(
            timestamp: now,
            sessionId: "s",
            cwd: "/r",
            gitBranch: nil,
            model: "claude-opus-4-7",
            tools: [],
            inputTokens: 100,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0
        )
        try await db.insertEvents(
            [event],
            from: "/test.jsonl",
            startingAt: 0,
            cursor: JSONLReader.Cursor()
        )

        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let model = AppModel(loginItem: LoginItemController(), preferences: prefs)

        // Inject a session block snapshot for the forecaster to consume.
        model.sessionBlock = SessionBlockSnapshot(
            startedAt: now.addingTimeInterval(-1800),
            resetsAt:  now.addingTimeInterval(16_200),
            usedFraction: 0.10,
            totalTokens: 1
        )

        let coord = try AppCoordinatorTestHook.make(model: model, db: db)
        await coord.refreshDerivedNow()

        XCTAssertNotNil(model.forecastBlock)
        XCTAssertNotNil(model.weekDelta)
        XCTAssertEqual(model.modelMix[.opus] ?? 0, 1.0, accuracy: 0.0001)
    }
}
