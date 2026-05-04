import Foundation

/// Streams JSONL lines from a file, supporting incremental reads via byte-offset cursors.
public final class JSONLReader {
    public struct Cursor: Codable, Equatable {
        public var offset: UInt64
        public var inode: UInt64
        public var deviceId: UInt64
        /// File size at last read. Detects truncation: if current size < this, file was rewritten.
        public var sizeAtLastRead: UInt64

        public init(offset: UInt64 = 0, inode: UInt64 = 0, deviceId: UInt64 = 0, sizeAtLastRead: UInt64 = 0) {
            self.offset = offset
            self.inode = inode
            self.deviceId = deviceId
            self.sizeAtLastRead = sizeAtLastRead
        }
    }

    public init() {}

    /// Read every line from `cursor.offset` to EOF. Returns updated cursor.
    /// Resets offset to 0 if (inode, dev) changed (rotation), or current size < cursor.sizeAtLastRead (truncation),
    /// or current size < cursor.offset (impossible without truncation).
    public func readNew(at url: URL, from cursor: Cursor) throws -> (lines: [Data], cursor: Cursor) {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let inode = (attrs[.systemFileNumber] as? UInt64) ?? 0
        let deviceId = (attrs[.deviceIdentifier] as? UInt64) ?? 0
        let currentSize = (attrs[.size] as? UInt64) ?? 0

        let identityChanged = inode != cursor.inode || deviceId != cursor.deviceId
        let truncated = currentSize < cursor.sizeAtLastRead || currentSize < cursor.offset
        let startOffset: UInt64 = (identityChanged || truncated) ? 0 : cursor.offset

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: startOffset)
        let data = handle.readDataToEndOfFile()
        let endOffset = startOffset + UInt64(data.count)

        let lines = Self.splitLines(data)
        return (lines, Cursor(offset: endOffset, inode: inode, deviceId: deviceId, sizeAtLastRead: endOffset))
    }

    static func splitLines(_ data: Data) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        for i in data.indices where data[i] == 0x0A {
            if i > start { lines.append(data.subdata(in: start..<i)) }
            start = data.index(after: i)
        }
        if start < data.endIndex { lines.append(data.subdata(in: start..<data.endIndex)) }
        return lines
    }
}
