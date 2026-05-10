import XCTest
@testable import ClaudegrainApp

@MainActor
final class PreferencesFixedSectionsTests: XCTestCase {
    /// `Preferences.fixedSections` must round-trip through UserDefaults so
    /// the user's per-section opt-in survives an app restart. Empty by
    /// default so fresh installs get the safe minimum receipt.
    func testFixedSectionsDefaultIsEmpty() {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = Preferences(defaults: suite)
        XCTAssertTrue(prefs.fixedSections.isEmpty)
    }

    func testFixedSectionsRoundTrip() {
        let suiteName = UUID().uuidString
        let suite = UserDefaults(suiteName: suiteName)!

        let prefs1 = Preferences(defaults: suite)
        prefs1.fixedSections = [.topTools, .heatmap]

        // Re-read from a fresh Preferences pointed at the same backing
        // store — proves the JSON encoded payload is what got persisted,
        // not just an in-memory cache.
        let prefs2 = Preferences(defaults: suite)
        XCTAssertEqual(prefs2.fixedSections, [.topTools, .heatmap])
    }

    func testFixedSectionsHonorEachToggle() {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = Preferences(defaults: suite)

        for section in FixedSection.allCases {
            prefs.fixedSections = [section]
            XCTAssertEqual(prefs.fixedSections, [section],
                           "section \(section) failed to round-trip in isolation")
        }

        prefs.fixedSections = Set(FixedSection.allCases)
        XCTAssertEqual(prefs.fixedSections.count, FixedSection.allCases.count)
    }

    /// AppModel.showsSection bridges layoutMode + fixedSections. Scroll mode
    /// always renders everything; fixed mode only what the user opted into.
    func testShowsSectionInScrollModeAlwaysTrue() {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = Preferences(defaults: suite)
        prefs.layoutMode = .scroll
        prefs.fixedSections = []      // intentionally empty

        let model = AppModel(loginItem: LoginItemController(), preferences: prefs)
        for section in FixedSection.allCases {
            XCTAssertTrue(model.showsSection(section),
                          "scroll mode should render \(section) regardless of opt-in")
        }
    }

    func testShowsSectionInFixedModeRespectsOptIn() {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = Preferences(defaults: suite)
        prefs.layoutMode = .fixed
        prefs.fixedSections = [.topTools]

        let model = AppModel(loginItem: LoginItemController(), preferences: prefs)
        XCTAssertTrue(model.showsSection(.topTools))
        XCTAssertFalse(model.showsSection(.heatmap))
        XCTAssertFalse(model.showsSection(.modelMix))
        XCTAssertFalse(model.showsSection(.weekDelta))
        XCTAssertFalse(model.showsSection(.subtotals))
    }
}
