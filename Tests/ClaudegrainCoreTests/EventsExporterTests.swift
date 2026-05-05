import XCTest
@testable import ClaudegrainCore

final class EventsExporterTests: XCTestCase {
    func testEnumRawValues() {
        XCTAssertEqual(ExportDimension.perRepoDaily.rawValue,  "per-repo daily")
        XCTAssertEqual(ExportDimension.perToolDaily.rawValue,  "per-tool daily")
        XCTAssertEqual(ExportDimension.perModelDaily.rawValue, "per-model daily")
        XCTAssertEqual(ExportDimension.rawEvents.rawValue,     "raw events")
        XCTAssertEqual(ExportFormat.csv.rawValue,  "csv")
        XCTAssertEqual(ExportFormat.json.rawValue, "json")
    }

    func testExporterInit() async throws {
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cg-export-\(UUID().uuidString).db")
        let db = try EventsDatabase(url: dbURL)
        _ = EventsExporter(db: db)
    }
}
