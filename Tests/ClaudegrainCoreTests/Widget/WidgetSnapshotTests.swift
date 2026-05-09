import XCTest
@testable import ClaudegrainCore

final class WidgetSnapshotTests: XCTestCase {

    private func tempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WidgetSnapshotTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sample() -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000_000),
            language: "en",
            primaryMetric: "spend",
            dataSourceStatus: "oauthLive",
            sessionBlockPercent: 0.47,
            sessionBlockResetAt: Date(timeIntervalSince1970: 1_010_000),
            weeklyPercent: 0.31,
            todayCostUSD: 3.42,
            todayTokens: 1_200_000,
            weekSpend: [0.5, 1.0, 0.7, 1.4, 2.0, 1.1, 3.42],
            topRepos: [
                .init(name: "menu-hub", costUSD: 1.80, percentOfDay: 0.53),
                .init(name: "prism-endpoint", costUSD: 0.90, percentOfDay: 0.26),
                .init(name: "dotfiles", costUSD: 0.30, percentOfDay: 0.09),
            ],
            cacheHitRate: 0.87
        )
    }

    func testRoundTripCodable() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let io = WidgetSnapshotIO(directory: dir)
        let original = sample()
        try io.write(original)
        let restored = io.read()

        XCTAssertEqual(restored, original)
    }

    func testReadMissingFileReturnsNil() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let io = WidgetSnapshotIO(directory: dir)
        XCTAssertNil(io.read())
    }

    func testCorruptedJSONReturnsNil() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let io = WidgetSnapshotIO(directory: dir)
        try Data("not json at all".utf8).write(to: io.fileURL)
        XCTAssertNil(io.read())
    }

    func testHigherSchemaVersionRejected() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let io = WidgetSnapshotIO(directory: dir)

        // Forge a JSON blob with a schemaVersion in the future.
        let future: [String: Any] = [
            "schemaVersion": WidgetSnapshot.currentSchemaVersion + 99,
            "generatedAt": "2026-05-10T00:00:00Z",
            "language": "en",
            "primaryMetric": "spend",
            "dataSourceStatus": "oauthLive",
            "sessionBlockPercent": 0.5,
            "weeklyPercent": 0.2,
            "todayCostUSD": 1.0,
            "todayTokens": 100,
            "weekSpend": [],
            "topRepos": [],
            "cacheHitRate": 0.0,
        ]
        let data = try JSONSerialization.data(withJSONObject: future)
        try data.write(to: io.fileURL)

        XCTAssertNil(io.read(), "Snapshots from a newer schema must be ignored, not crash.")
    }

    func testEmptySnapshotConstructs() {
        let snap = WidgetSnapshot.empty(language: "zh")
        XCTAssertEqual(snap.schemaVersion, WidgetSnapshot.currentSchemaVersion)
        XCTAssertEqual(snap.language, "zh")
        XCTAssertEqual(snap.todayCostUSD, 0)
        XCTAssertTrue(snap.weekSpend.isEmpty)
        XCTAssertTrue(snap.topRepos.isEmpty)
    }

    func testWriteCreatesParentDirectory() throws {
        let dir = tempDir().appendingPathComponent("nested/dir/that/does/not/exist")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let io = WidgetSnapshotIO(directory: dir)
        XCTAssertNoThrow(try io.write(sample()))
        XCTAssertNotNil(io.read())
    }
}
