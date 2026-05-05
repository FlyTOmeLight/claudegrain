import Foundation

public struct QuietHours: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var startHour: Int    // 0–23 device-local
    public var startMinute: Int  // 0–59
    public var endHour: Int      // 0–23 device-local
    public var endMinute: Int    // 0–59

    public init(enabled: Bool, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.enabled = enabled
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    public static let `default` = QuietHours(
        enabled: false, startHour: 22, startMinute: 0, endHour: 9, endMinute: 0
    )

    /// Returns true iff `date`'s local time is in `[start, end)`. Window may
    /// span midnight (start > end → wraps next day). `enabled == false` always
    /// returns false.
    public func contains(_ date: Date) -> Bool {
        guard enabled else { return false }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let startMin = startHour * 60 + startMinute
        let endMin = endHour * 60 + endMinute
        if startMin == endMin { return false }   // empty window
        if startMin < endMin {
            return nowMin >= startMin && nowMin < endMin
        } else {
            return nowMin >= startMin || nowMin < endMin
        }
    }
}
