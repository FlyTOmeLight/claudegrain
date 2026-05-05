import XCTest
@testable import ClaudegrainCore
@testable import ClaudegrainApp

@MainActor
final class IngestPauseControllerTests: XCTestCase {
    func testInitDefaultsToNotPaused() {
        let controller = IngestPauseController(defaults: UserDefaults(suiteName: "pause-\(UUID().uuidString)")!)
        XCTAssertFalse(controller.isPaused)
    }

    func testToggleAndPersist() {
        let defaults = UserDefaults(suiteName: "pause-\(UUID().uuidString)")!
        let c1 = IngestPauseController(defaults: defaults)
        c1.pause()
        XCTAssertTrue(c1.isPaused)

        let c2 = IngestPauseController(defaults: defaults)
        XCTAssertTrue(c2.isPaused)

        c2.resume()
        XCTAssertFalse(c2.isPaused)
    }
}
