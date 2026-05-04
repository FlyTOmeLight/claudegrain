import SwiftUI

/// V18 token palette — single source of truth for both popover and Settings.
struct Theme {
    let paperBg: Color
    let ink: Color
    let inkBold: Color
    let inkFaint: Color
    let warn: Color
    let crit: Color
    let pulse: Color
    let opus: Color
    let sonnet: Color
    let haiku: Color
    let scanlineOpacity: Double
    let glowEnabled: Bool

    static let phosphor = Theme(
        paperBg: Color(red: 0x04 / 255, green: 0x06 / 255, blue: 0x0A / 255),
        ink: Color(red: 0xB8 / 255, green: 0xF0 / 255, blue: 0xD2 / 255),
        inkBold: Color(red: 0x6D / 255, green: 0xFF / 255, blue: 0xAE / 255),
        inkFaint: Color(red: 0x5A / 255, green: 0x8A / 255, blue: 0x72 / 255),
        warn: Color(red: 0xFF / 255, green: 0xD2 / 255, blue: 0x4A / 255),
        crit: Color(red: 0xFF / 255, green: 0x5C / 255, blue: 0x5C / 255),
        pulse: Color(red: 0xFF / 255, green: 0x3B / 255, blue: 0x3B / 255),
        opus: Color(red: 0x4D / 255, green: 0xD2 / 255, blue: 0xFF / 255),
        sonnet: Color(red: 0x6D / 255, green: 0xFF / 255, blue: 0xAE / 255),
        haiku: Color(red: 0x88 / 255, green: 0x88 / 255, blue: 0x88 / 255),
        scanlineOpacity: 0.025,
        glowEnabled: true
    )

    static let thermal = Theme(
        paperBg: Color(red: 0xF7 / 255, green: 0xF1 / 255, blue: 0xDE / 255),
        ink: Color(red: 0x1D / 255, green: 0x2D / 255, blue: 0x20 / 255),
        inkBold: Color(red: 0x15 / 255, green: 0x69 / 255, blue: 0x3A / 255),
        inkFaint: Color(red: 0x6A / 255, green: 0x7A / 255, blue: 0x6A / 255),
        warn: Color(red: 0xA0 / 255, green: 0x6B / 255, blue: 0x00 / 255),
        crit: Color(red: 0xB3 / 255, green: 0x24 / 255, blue: 0x22 / 255),
        pulse: Color(red: 0xC0 / 255, green: 0x20 / 255, blue: 0x2B / 255),
        opus: Color(red: 0x1E / 255, green: 0x3A / 255, blue: 0x8A / 255),
        sonnet: Color(red: 0x1A / 255, green: 0x7A / 255, blue: 0x4A / 255),
        haiku: Color(red: 0x88 / 255, green: 0x88 / 255, blue: 0x88 / 255),
        scanlineOpacity: 0.0,
        glowEnabled: false
    )
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.phosphor
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Font {
    static let cgMono = Font.custom("JetBrains Mono", size: 11)
    static let cgMonoSmall = Font.custom("JetBrains Mono", size: 9)
    static let cgMonoXSmall = Font.custom("JetBrains Mono", size: 8.5)
    static let cgMonoTiny = Font.custom("JetBrains Mono", size: 7.5)
    static let cgMonoMed = Font.custom("JetBrains Mono", size: 10)
    static let cgMonoBold = Font.custom("JetBrains Mono", size: 11).weight(.bold)
    static let cgDisplay = Font.custom("Space Mono", size: 48).weight(.bold)
    static let cgDisplayBold = Font.custom("Space Mono", size: 12).weight(.bold)
}
