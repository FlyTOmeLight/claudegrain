import SwiftUI

/// macOS function-key `KeyEquivalent`s. SwiftUI's `KeyEquivalent` does not
/// expose `.f1`..`.f12` constants, so we build them from NSEvent's well-known
/// unicode scalars (`NSF1FunctionKey` = 0xF704, etc.).
extension KeyEquivalent {
    static var fnF2: KeyEquivalent { KeyEquivalent(Character(UnicodeScalar(0xF705)!)) }
    static var fnF5: KeyEquivalent { KeyEquivalent(Character(UnicodeScalar(0xF708)!)) }
    static var fnF10: KeyEquivalent { KeyEquivalent(Character(UnicodeScalar(0xF70D)!)) }
}

/// Canonical animation tokens for the V18 Phosphor Receipt UI.
/// Single source of truth — never inline `.easeInOut(duration:)` etc.
extension Animation {
    /// 0.15s easeOut. Tap feedback, tab indicator move, hover state.
    static let cgFast: Animation = .easeOut(duration: 0.15)

    /// 0.30s easeInOut. Banner show/hide, cross-fade, status dot color change.
    static let cgMedium: Animation = .easeInOut(duration: 0.30)

    /// 0.50s easeInOut. Section transitions (rare).
    static let cgSlow: Animation = .easeInOut(duration: 0.50)

    /// Continuous spinner. 0.7s linear repeating.
    static let cgSpin: Animation = .linear(duration: 0.7).repeatForever(autoreverses: false)

    /// Attention pulse. 0.7s easeInOut auto-reversing.
    static let cgPulse: Animation = .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
}

enum Motion {
    /// Returns the given animation, or a zero-duration linear when Reduce Motion is on.
    /// Use for any view-driven animation that should freeze under accessibility settings.
    @MainActor
    static func preferred(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0) : animation
    }
}
