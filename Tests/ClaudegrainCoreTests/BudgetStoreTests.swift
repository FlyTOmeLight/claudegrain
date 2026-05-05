import XCTest
@testable import ClaudegrainCore

@MainActor
final class BudgetStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "budget-test-\(UUID().uuidString)")!
    }

    func testDefaultsAreEmpty() {
        let store = BudgetStore(defaults: makeDefaults())
        XCTAssertTrue(store.allBudgets.isEmpty)
        XCTAssertEqual(store.globalDefaultDailyUSD, 10.0, accuracy: 0.001)
    }

    func testSetAndResolveBudget() {
        let store = BudgetStore(defaults: makeDefaults())
        store.setBudget(repo: "/a", daily: 5.0, weekly: 30.0)

        let resolved = store.resolve(repo: "/a")
        XCTAssertEqual(resolved.dailyUSD, 5.0)
        XCTAssertEqual(resolved.weeklyUSD, 30.0)
        XCTAssertEqual(resolved.repo, "/a")
    }

    func testResolveFallsBackToGlobalDefault() {
        let store = BudgetStore(defaults: makeDefaults())
        store.globalDefaultDailyUSD = 7.5

        let resolved = store.resolve(repo: "/never-set")
        XCTAssertEqual(resolved.dailyUSD, 7.5)
        XCTAssertNil(resolved.weeklyUSD)
        XCTAssertEqual(resolved.repo, "/never-set")
    }

    func testPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let s1 = BudgetStore(defaults: defaults)
        s1.setBudget(repo: "/x", daily: 12.0, weekly: nil)
        s1.globalDefaultDailyUSD = 4.0

        let s2 = BudgetStore(defaults: defaults)
        XCTAssertEqual(s2.resolve(repo: "/x").dailyUSD, 12.0)
        XCTAssertEqual(s2.globalDefaultDailyUSD, 4.0)
    }

    func testRemoveBudget() {
        let store = BudgetStore(defaults: makeDefaults())
        store.setBudget(repo: "/a", daily: 5.0, weekly: nil)
        store.removeBudget(repo: "/a")
        XCTAssertNil(store.allBudgets["/a"])
        XCTAssertEqual(store.resolve(repo: "/a").dailyUSD, store.globalDefaultDailyUSD)
    }

    func testMigratesLegacyRepoOverspendThreshold() {
        let defaults = makeDefaults()
        defaults.set(15.0, forKey: "repoOverspendThresholdUSD")

        let store = BudgetStore(defaults: defaults)
        store.migrateLegacyKeyIfNeeded()

        XCTAssertEqual(store.globalDefaultDailyUSD, 15.0, accuracy: 0.001)
        XCTAssertNil(defaults.object(forKey: "repoOverspendThresholdUSD"),
                     "legacy key should be removed after migration")
    }

    func testMigrationIsIdempotent() {
        let defaults = makeDefaults()
        defaults.set(15.0, forKey: "repoOverspendThresholdUSD")

        let s1 = BudgetStore(defaults: defaults)
        s1.migrateLegacyKeyIfNeeded()
        // Second call must not overwrite a user-set new-key value.
        s1.globalDefaultDailyUSD = 8.0
        s1.migrateLegacyKeyIfNeeded()
        XCTAssertEqual(s1.globalDefaultDailyUSD, 8.0)
    }

    func testMigrationDoesNothingWithoutLegacyKey() {
        let store = BudgetStore(defaults: makeDefaults())
        store.migrateLegacyKeyIfNeeded()
        XCTAssertEqual(store.globalDefaultDailyUSD, 10.0)
    }
}
