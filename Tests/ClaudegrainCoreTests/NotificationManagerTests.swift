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

    func testBurnRateFiresAtTwiceExpectedPace() {
        let (_, prefs) = makePrefs()
        prefs.notifyBurnRate = true
        var fired: [NotificationKind] = []
        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in fired.append(kind) }

        // 60 min into a 5h block (20% elapsed), used 50% → 2.5× pace.
        let started = Date().addingTimeInterval(-60 * 60)
        let resets = started.addingTimeInterval(5 * 3600)
        let s = SessionBlockSnapshot(startedAt: started, resetsAt: resets, usedFraction: 0.5, totalTokens: 0)
        mgr.evaluateUsage(session: s, weekly: nil, topRepos: [])
        XCTAssertEqual(fired, [.burnRate])

        // No refire while still hot.
        mgr.evaluateUsage(session: s, weekly: nil, topRepos: [])
        XCTAssertEqual(fired, [.burnRate])
    }

    func testBurnRateNoFireOnPace() {
        let (_, prefs) = makePrefs()
        prefs.notifyBurnRate = true
        var fired: [NotificationKind] = []
        let mgr = NotificationManager(prefs: prefs) { kind, _, _ in fired.append(kind) }

        // 60 min into 5h, 22% used → only 1.1× pace, no fire.
        let started = Date().addingTimeInterval(-60 * 60)
        let resets = started.addingTimeInterval(5 * 3600)
        let s = SessionBlockSnapshot(startedAt: started, resetsAt: resets, usedFraction: 0.22, totalTokens: 0)
        mgr.evaluateUsage(session: s, weekly: nil, topRepos: [])
        XCTAssertTrue(fired.isEmpty)
    }

    func testRepoOverspendFiresPerRepoPerDay() {
        let (_, prefs) = makePrefs()
        prefs.notifyRepoOverspend = true
        prefs.repoOverspendThresholdUSD = 5.0
        var fired: [(NotificationKind, String)] = []
        let mgr = NotificationManager(prefs: prefs) { kind, title, _ in fired.append((kind, title)) }

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
