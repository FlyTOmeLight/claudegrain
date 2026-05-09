import Foundation
import Combine
import ClaudegrainCore

enum PrimaryMetric: String, CaseIterable, Codable {
    case sessionPercent
    case weeklyPercent
    case todayCost
    case cacheHit
}

enum AppLanguage: String, CaseIterable, Codable, Hashable {
    case english
    case chinese
}

enum LayoutMode: String, CaseIterable, Codable, Hashable {
    case scroll   // ScrollView wraps the receipt content
    case fixed    // Plain VStack — no scroll, popover sized to content
}

enum SoundChoice: Equatable, Hashable, Codable {
    case app
    case system(name: String)
    case imported(path: String)
}

@MainActor
final class Preferences: ObservableObject {
    enum Key {
        static let notifyThreshold = "notifyThreshold"
        static let notifyBurnRate = "notifyBurnRate"
        static let notifyBlockReset = "notifyBlockReset"
        static let notifyRepoOverspend = "notifyRepoOverspend"
        static let repoOverspendThresholdUSD = "repoOverspendThresholdUSD"
        static let primaryMetric = "primaryMetric"
        static let notificationSound = "notificationSound"
        static let language = "language"
        static let layoutMode = "layoutMode"
        static let quietHours = "quietHours.v1"
    }

    static let shared = Preferences()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.notifyThreshold: true,
            Key.notifyBurnRate: false,
            Key.notifyBlockReset: false,
            Key.notifyRepoOverspend: false,
            // repoOverspendThresholdUSD migrated to BudgetStore.globalDefaultDailyUSD;
            // omit from registration domain so process-wide registration doesn't leak
            // a default value into BudgetStoreTests' isolated suite migration check.
            Key.primaryMetric: PrimaryMetric.sessionPercent.rawValue,
            Key.language: AppLanguage.chinese.rawValue,
            Key.layoutMode: LayoutMode.scroll.rawValue,
        ])
    }

    var language: AppLanguage {
        get {
            let raw = defaults.string(forKey: Key.language) ?? AppLanguage.chinese.rawValue
            return AppLanguage(rawValue: raw) ?? .chinese
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.language)
            objectWillChange.send()
        }
    }

    var layoutMode: LayoutMode {
        get {
            let raw = defaults.string(forKey: Key.layoutMode) ?? LayoutMode.scroll.rawValue
            return LayoutMode(rawValue: raw) ?? .scroll
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.layoutMode)
            objectWillChange.send()
        }
    }

    var repoOverspendThresholdUSD: Double {
        get { defaults.double(forKey: Key.repoOverspendThresholdUSD) }
        set {
            defaults.set(newValue, forKey: Key.repoOverspendThresholdUSD)
            objectWillChange.send()
        }
    }

    @Published var notifyThresholdCache: Bool = true
    @Published var notifyBurnRateCache: Bool = false
    @Published var notifyBlockResetCache: Bool = false
    @Published var notifyRepoOverspendCache: Bool = false

    var notifyThreshold: Bool {
        get { defaults.bool(forKey: Key.notifyThreshold) }
        set {
            defaults.set(newValue, forKey: Key.notifyThreshold)
            notifyThresholdCache = newValue
            objectWillChange.send()
        }
    }

    var notifyBurnRate: Bool {
        get { defaults.bool(forKey: Key.notifyBurnRate) }
        set {
            defaults.set(newValue, forKey: Key.notifyBurnRate)
            notifyBurnRateCache = newValue
            objectWillChange.send()
        }
    }

    var notifyBlockReset: Bool {
        get { defaults.bool(forKey: Key.notifyBlockReset) }
        set {
            defaults.set(newValue, forKey: Key.notifyBlockReset)
            notifyBlockResetCache = newValue
            objectWillChange.send()
        }
    }

    var notifyRepoOverspend: Bool {
        get { defaults.bool(forKey: Key.notifyRepoOverspend) }
        set {
            defaults.set(newValue, forKey: Key.notifyRepoOverspend)
            notifyRepoOverspendCache = newValue
            objectWillChange.send()
        }
    }

    var primaryMetric: PrimaryMetric {
        get {
            let raw = defaults.string(forKey: Key.primaryMetric) ?? PrimaryMetric.sessionPercent.rawValue
            return PrimaryMetric(rawValue: raw) ?? .sessionPercent
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.primaryMetric)
            objectWillChange.send()
        }
    }

    var notificationSoundChoice: SoundChoice {
        get {
            guard let data = defaults.data(forKey: Key.notificationSound),
                  let decoded = try? JSONDecoder().decode(SoundChoice.self, from: data)
            else { return .app }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.notificationSound)
            }
            objectWillChange.send()
        }
    }

    var quietHours: QuietHours {
        get {
            guard let data = defaults.data(forKey: Key.quietHours),
                  let q = try? JSONDecoder().decode(QuietHours.self, from: data)
            else { return .default }
            return q
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.quietHours)
            }
            objectWillChange.send()
        }
    }
}
