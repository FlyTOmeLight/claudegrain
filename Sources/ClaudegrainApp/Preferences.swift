import Foundation
import Combine

enum PrimaryMetric: String, CaseIterable, Codable {
    case sessionPercent
    case weeklyPercent
    case todayCost
    case cacheHit
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
        static let primaryMetric = "primaryMetric"
        static let notificationSound = "notificationSound"
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
            Key.primaryMetric: PrimaryMetric.sessionPercent.rawValue,
        ])
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
}
