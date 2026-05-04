import AppKit
import CoreText
import OSLog

private let log = Logger(subsystem: "dev.claudegrain.menubar", category: "fonts")

/// Registers bundled .ttf fonts at app launch so SwiftUI `.font(.custom(...))`
/// can resolve them regardless of system installation.
enum FontRegistry {
    static func registerAll() {
        let names = [
            "JetBrainsMono-Regular",
            "JetBrainsMono-Bold",
            "SpaceMono-Regular",
            "SpaceMono-Bold",
        ]
        for name in names {
            register(name: name)
        }
    }

    private static func register(name: String) {
        // SwiftPM's `Bundle.module` lookup is broken inside macOS .app bundles
        // (it does not check Contents/Resources/), so resolve the resource bundle
        // manually relative to the main bundle.
        let resourceBundle: Bundle? = {
            let candidates = [
                Bundle.main.resourceURL?.appendingPathComponent("claudegrain_ClaudegrainApp.bundle"),
                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/claudegrain_ClaudegrainApp.bundle"),
                Bundle.main.bundleURL.appendingPathComponent("claudegrain_ClaudegrainApp.bundle"),
            ].compactMap { $0 }
            for url in candidates {
                if FileManager.default.fileExists(atPath: url.path) {
                    return Bundle(url: url)
                }
            }
            return nil
        }()

        let candidates: [URL?] = [
            resourceBundle?.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts"),
            resourceBundle?.url(forResource: name, withExtension: "ttf"),
            Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts"),
            Bundle.main.url(forResource: name, withExtension: "ttf"),
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            log.warning("font \(name) not found in bundle")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Already registered is fine.
            log.debug("font register skipped \(name): \(String(describing: error?.takeRetainedValue()))")
        }
    }
}
