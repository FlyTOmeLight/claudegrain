import Foundation
import Combine

@MainActor
public final class IngestPauseController: ObservableObject {
    public static let key = "ingestPaused.v1"

    @Published public private(set) var isPaused: Bool

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPaused = defaults.bool(forKey: Self.key)
    }

    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        defaults.set(true, forKey: Self.key)
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        defaults.set(false, forKey: Self.key)
    }

    public func toggle() {
        if isPaused { resume() } else { pause() }
    }
}
