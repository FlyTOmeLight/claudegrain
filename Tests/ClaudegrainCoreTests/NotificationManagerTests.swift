import XCTest
@testable import ClaudegrainApp
@testable import ClaudegrainCore

@MainActor
final class NotificationManagerTests: XCTestCase {
    private func makePrefs(suite: String = UUID().uuidString) -> (UserDefaults, Preferences) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = Preferences(defaults: defaults)
        return (defaults, prefs)
    }

    private func session(used: Double, started: Date = Date(timeIntervalSince1970: 1_000),
                         resets: Date = Date(timeIntervalSinceNow: 3600)) -> SessionBlockSnapshot {
        SessionBlockSnapshot(startedAt: started, resetsAt: resets, usedFraction: used, totalTokens: 0)
    }

    private func weekly(used: Double,
                        resets: Date = Date(timeIntervalSinceNow: 86_400)) -> WeeklyUsageSnapshot {
        WeeklyUsageSnapshot(usedFraction: used, resetsAt: resets)
    }

    func testFiresOnceWhenSessionCrosses70() {
        let (_, prefs) = makePrefs()
        var fired: [NotificationKind] = []
        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in fired.append(kind) }

        mgr.evaluate(session: session(used: 0.5), weekly: nil)
        XCTAssertTrue(fired.isEmpty)

        mgr.evaluate(session: session(used: 0.72), weekly: nil)
        XCTAssertEqual(fired, [.sessionWarn70])

        mgr.evaluate(session: session(used: 0.75), weekly: nil)
        XCTAssertEqual(fired, [.sessionWarn70], "should not refire within same block")
    }

    func testEscalatesTo90AfterWarning() {
        let (_, prefs) = makePrefs()
        var fired: [NotificationKind] = []
        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in fired.append(kind) }

        mgr.evaluate(session: session(used: 0.72), weekly: nil)
        mgr.evaluate(session: session(used: 0.91), weekly: nil)
        XCTAssertEqual(fired, [.sessionWarn70, .sessionCritical90])

        mgr.evaluate(session: session(used: 0.95), weekly: nil)
        XCTAssertEqual(fired, [.sessionWarn70, .sessionCritical90])
    }

    func testNewSessionBlockResetsCooldown() {
        let (_, prefs) = makePrefs()
        var fired: [NotificationKind] = []
        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in fired.append(kind) }

        let blockA = Date(timeIntervalSince1970: 1_000)
        let blockB = Date(timeIntervalSince1970: 2_000)
        mgr.evaluate(session: session(used: 0.72, started: blockA), weekly: nil)
        mgr.evaluate(session: session(used: 0.72, started: blockA), weekly: nil)
        mgr.evaluate(session: session(used: 0.72, started: blockB), weekly: nil)
        XCTAssertEqual(fired, [.sessionWarn70, .sessionWarn70])
    }

    func testWeeklyFiresOnceAt85() {
        let (_, prefs) = makePrefs()
        var fired: [NotificationKind] = []
        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in fired.append(kind) }
        let resets = Date(timeIntervalSince1970: 5_000_000)

        mgr.evaluate(session: nil, weekly: weekly(used: 0.84, resets: resets))
        XCTAssertTrue(fired.isEmpty)

        mgr.evaluate(session: nil, weekly: weekly(used: 0.86, resets: resets))
        mgr.evaluate(session: nil, weekly: weekly(used: 0.92, resets: resets))
        XCTAssertEqual(fired, [.weeklyWarn85])
    }

    func testThresholdToggleOffSilences() {
        let (_, prefs) = makePrefs()
        prefs.notifyThreshold = false
        var fired: [NotificationKind] = []
        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in fired.append(kind) }

        mgr.evaluate(session: session(used: 0.95), weekly: weekly(used: 0.99))
        XCTAssertTrue(fired.isEmpty)
    }

    func testBlockResetSoonRequiresToggle() {
        let (_, prefs) = makePrefs()
        var fired: [NotificationKind] = []
        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in fired.append(kind) }

        let soon = Date(timeIntervalSinceNow: 300)
        mgr.evaluate(session: session(used: 0.4, resets: soon), weekly: nil)
        XCTAssertTrue(fired.isEmpty, "block-reset toggle defaults off")

        prefs.notifyBlockReset = true
        mgr.evaluate(session: session(used: 0.4, resets: soon), weekly: nil)
        XCTAssertEqual(fired, [.blockResetSoon])

        mgr.evaluate(session: session(used: 0.4, resets: soon), weekly: nil)
        XCTAssertEqual(fired, [.blockResetSoon], "no refire for same block")
    }

    func testRepoOverspendFiresPerRepoPerDay() {
        let (_, prefs) = makePrefs()
        prefs.notifyRepoOverspend = true
        let budgets = BudgetStore(defaults: UserDefaults(suiteName: "rospd-\(UUID().uuidString)")!)
        budgets.globalDefaultDailyUSD = 5.0
        var fired: [(NotificationKind, String)] = []
        let mgr = NotificationManager(prefs: prefs, budgets: budgets) { kind, title, _ in fired.append((kind, title)) }

        let repos = [
            RepoBreakdown(repo: "a", fullCwd: "/a", costUSD: 6.0, totalTokens: 0),
            RepoBreakdown(repo: "b", fullCwd: "/b", costUSD: 3.0, totalTokens: 0),
        ]
        mgr.evaluateUsage(session: nil, weekly: nil, topRepos: repos)
        XCTAssertEqual(fired.count, 1)
        XCTAssertTrue(fired[0].1.contains("a"))

        // Re-evaluate: should not refire same repo same day.
        mgr.evaluateUsage(session: nil, weekly: nil, topRepos: repos)
        XCTAssertEqual(fired.count, 1)
    }

    func testBurnRateFiresOnForecasterMediumOrAbove() {
        var fired: [NotificationKind] = []
        let prefs = Preferences(defaults: UserDefaults(suiteName: "burn-\(UUID().uuidString)")!)
        prefs.notifyBurnRate = true

        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in
            fired.append(kind)
        }
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt: now.addingTimeInterval(-1800),
            resetsAt:  now.addingTimeInterval(16_200),
            usedFraction: 0.6,
            totalTokens: 1
        )

        mgr.evaluateBurnRate(session: snap, forecast: ForecastResult(
            willHit: true,
            hitAt: now.addingTimeInterval(1200),
            confidence: .medium,
            basis: .ewma
        ))

        XCTAssertEqual(fired, [.burnRate])
    }

    func testBurnRateDoesNotFireOnLowConfidence() {
        var fired: [NotificationKind] = []
        let prefs = Preferences(defaults: UserDefaults(suiteName: "burn-low-\(UUID().uuidString)")!)
        prefs.notifyBurnRate = true

        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in
            fired.append(kind)
        }
        let now = Date()
        let snap = SessionBlockSnapshot(
            startedAt: now.addingTimeInterval(-1800),
            resetsAt:  now.addingTimeInterval(16_200),
            usedFraction: 0.6,
            totalTokens: 1
        )

        mgr.evaluateBurnRate(session: snap, forecast: ForecastResult(
            willHit: true,
            hitAt: now.addingTimeInterval(1200),
            confidence: .low,
            basis: .ewma
        ))

        XCTAssertTrue(fired.isEmpty)
    }

    func testRepoOverspendUsesPerRepoBudget() {
        var fired: [(NotificationKind, String)] = []
        let prefs = Preferences(defaults: UserDefaults(suiteName: "ros-\(UUID().uuidString)")!)
        prefs.notifyRepoOverspend = true

        let budgets = BudgetStore(defaults: UserDefaults(suiteName: "ros-budgets-\(UUID().uuidString)")!)
        budgets.globalDefaultDailyUSD = 100.0   // very high default
        budgets.setBudget(repo: "/tight", daily: 1.0, weekly: nil)

        let mgr = NotificationManager(prefs: prefs, budgets: budgets) { kind, _, body in
            fired.append((kind, body))
        }

        let topRepos: [RepoBreakdown] = [
            RepoBreakdown(repo: "/tight", fullCwd: "/tight", costUSD: 5.0, totalTokens: 1),
            RepoBreakdown(repo: "/loose", fullCwd: "/loose", costUSD: 50.0, totalTokens: 1),
        ]

        mgr.evaluateUsage(session: nil, weekly: nil, topRepos: topRepos)

        XCTAssertEqual(fired.count, 1, "/tight should fire (5.0 > 1.0); /loose stays under 100.0")
        XCTAssertEqual(fired.first?.0, .repoOverspend)
        XCTAssertTrue(fired.first?.1.contains("/tight") ?? false)
    }

    func testQuietHoursSuppressesAllNotifications() {
        var fired: [NotificationKind] = []
        let prefs = Preferences(defaults: UserDefaults(suiteName: "qh-\(UUID().uuidString)")!)
        prefs.notifyThreshold = true
        prefs.quietHours = QuietHours(enabled: true,
                                       startHour: 0, startMinute: 0,
                                       endHour: 23, endMinute: 59)   // all-day suppress for test

        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in fired.append(kind) }
        let snap = SessionBlockSnapshot(
            startedAt: Date().addingTimeInterval(-1800),
            resetsAt:  Date().addingTimeInterval(16_200),
            usedFraction: 0.95,
            totalTokens: 1
        )
        mgr.evaluate(session: snap, weekly: nil)

        XCTAssertTrue(fired.isEmpty, "quiet hours should suppress threshold notification")
    }

    func testPreferencesPersistAcrossInstances() {
        let suite = "claudegrain.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let p1 = Preferences(defaults: defaults)
        XCTAssertTrue(p1.notifyThreshold)
        p1.notifyThreshold = false
        p1.notifyBurnRate = true
        p1.primaryMetric = .weeklyPercent

        let p2 = Preferences(defaults: defaults)
        XCTAssertFalse(p2.notifyThreshold)
        XCTAssertTrue(p2.notifyBurnRate)
        XCTAssertEqual(p2.primaryMetric, .weeklyPercent)
    }
}
