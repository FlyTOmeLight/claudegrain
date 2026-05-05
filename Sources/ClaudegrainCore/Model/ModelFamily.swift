public enum ModelFamily: Hashable, Sendable {
    case opus
    case sonnet
    case haiku
    case unknown

    /// Match family by substring on the model id. Order matters: more specific first.
    /// Pure string matching, no allocation beyond `lowercased()`.
    public static func parse(_ id: String) -> ModelFamily {
        let lower = id.lowercased()
        if lower.contains("opus")   { return .opus }
        if lower.contains("sonnet") { return .sonnet }
        if lower.contains("haiku")  { return .haiku }
        return .unknown
    }
}
