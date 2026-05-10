import Foundation

extension Bundle {
    /// Full marketing version — e.g. "1.0.0".
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Compact major.minor — e.g. "1.0". Used for the receipt's tagline and
    /// the footer's `0xCG-V…` serial where the patch component would crowd
    /// the layout.
    static var appVersionShort: String {
        let parts = appVersion.split(separator: ".")
        return parts.count >= 2 ? "\(parts[0]).\(parts[1])" : appVersion
    }
}
