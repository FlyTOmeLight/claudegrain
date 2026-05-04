import XCTest
@testable import ClaudegrainApp

@MainActor
final class LoginItemControllerTests: XCTestCase {
    /// Init must read `SMAppService.mainApp.status` without throwing or
    /// crashing. In a CI sandbox the bundle has no proper identifier, so
    /// status is typically `.notRegistered` -> `isEnabled == false`.
    /// Real register/unregister behavior cannot be exercised here.
    func testInitReadsStatusWithoutCrashing() {
        let controller = LoginItemController()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNil(controller.lastError)
    }

    func testRefreshIsIdempotent() {
        let controller = LoginItemController()
        let before = controller.isEnabled
        controller.refresh()
        XCTAssertEqual(controller.isEnabled, before)
    }
}
