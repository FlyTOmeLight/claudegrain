import Foundation

/// Atomic JSON writer for `WidgetSnapshot`. Targets the App Group container
/// when running inside an entitled host; falls back to a caller-supplied
/// directory for unit tests. Snapshots produced with a higher schemaVersion
/// than the reader knows about are dropped — the extension treats unknown
/// versions as "no snapshot" rather than crashing.
public struct WidgetSnapshotIO: Sendable {
    public static let fileName = "widget-snapshot.json"
    public static let appGroupID = "group.dev.claudegrain.shared"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Convenience initializer that resolves the App Group container.
    /// Returns nil when the host is unsigned / not entitled — in that case
    /// the caller should fall back to Application Support.
    public static func appGroupContainer() -> WidgetSnapshotIO? {
        let fm = FileManager.default
        guard let url = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        return WidgetSnapshotIO(directory: url)
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// Writes the snapshot atomically (`.atomic`). Creates the directory if
    /// needed. Throws on encode or write failure.
    public func write(_ snapshot: WidgetSnapshot) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Reads the latest snapshot. Returns nil when the file is absent,
    /// undecodable, or stamped with a higher schemaVersion than this build
    /// supports.
    public func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snap = try? decoder.decode(WidgetSnapshot.self, from: data) else {
            return nil
        }
        guard snap.schemaVersion <= WidgetSnapshot.currentSchemaVersion else {
            return nil
        }
        return snap
    }
}
