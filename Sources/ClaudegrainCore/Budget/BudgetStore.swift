import Foundation

public struct RepoBudget: Codable, Equatable, Sendable {
    public let repo: String
    public let dailyUSD: Double?
    public let weeklyUSD: Double?

    public init(repo: String, dailyUSD: Double?, weeklyUSD: Double?) {
        self.repo = repo
        self.dailyUSD = dailyUSD
        self.weeklyUSD = weeklyUSD
    }
}

/// Per-repo soft budgets (ADR-0008). Replaces the single
/// `repoOverspendThresholdUSD` value used in 0.1.x.
@MainActor
public final class BudgetStore: ObservableObject {
    public static let budgetsKey = "budgets.v2"
    public static let globalDailyKey = "globalDefaultDailyUSD"

    @Published public private(set) var allBudgets: [String: RepoBudget] = [:]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.allBudgets = Self.load(from: defaults)
    }

    public var globalDefaultDailyUSD: Double {
        get {
            // Returns 10.0 if the key isn't present (first-run default).
            if defaults.object(forKey: Self.globalDailyKey) == nil { return 10.0 }
            return defaults.double(forKey: Self.globalDailyKey)
        }
        set {
            defaults.set(newValue, forKey: Self.globalDailyKey)
            objectWillChange.send()
        }
    }

    public func setBudget(repo: String, daily: Double?, weekly: Double?) {
        let budget = RepoBudget(repo: repo, dailyUSD: daily, weeklyUSD: weekly)
        allBudgets[repo] = budget
        save()
    }

    public func removeBudget(repo: String) {
        allBudgets.removeValue(forKey: repo)
        save()
    }

    /// Returns per-repo override if set, else the global default daily threshold.
    public func resolve(repo: String) -> RepoBudget {
        if let b = allBudgets[repo] { return b }
        return RepoBudget(repo: repo, dailyUSD: globalDefaultDailyUSD, weeklyUSD: nil)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(allBudgets) else { return }
        defaults.set(data, forKey: Self.budgetsKey)
    }

    private static func load(from defaults: UserDefaults) -> [String: RepoBudget] {
        guard let data = defaults.data(forKey: Self.budgetsKey),
              let map = try? JSONDecoder().decode([String: RepoBudget].self, from: data)
        else { return [:] }
        return map
    }
}
