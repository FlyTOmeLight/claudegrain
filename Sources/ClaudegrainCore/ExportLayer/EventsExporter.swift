import Foundation

public enum ExportDimension: String, CaseIterable, Sendable {
    case perRepoDaily   = "per-repo daily"
    case perToolDaily   = "per-tool daily"
    case perModelDaily  = "per-model daily"
    case rawEvents      = "raw events"
}

public enum ExportFormat: String, CaseIterable, Sendable {
    case csv  = "csv"
    case json = "json"
}

/// Writes aggregated or raw events to disk. ADR-0007: every export carries
/// a disclaimer header noting primaryTool attribution + price-table estimate.
public struct EventsExporter: Sendable {
    private let db: EventsDatabase

    public init(db: EventsDatabase) {
        self.db = db
    }

    /// Writes the export to `url`. Range is half-open `[range.start, range.end)`.
    public func export(
        range: DateInterval,
        dimension: ExportDimension,
        format: ExportFormat,
        to url: URL
    ) async throws {
        let payload: String
        switch format {
        case .csv:  payload = try await csvPayload(range: range, dimension: dimension)
        case .json: payload = try await jsonPayload(range: range, dimension: dimension)
        }
        try payload.write(to: url, atomically: true, encoding: .utf8)
    }

    private func csvPayload(range: DateInterval, dimension: ExportDimension) async throws -> String {
        var out = csvHeader(range: range, dimension: dimension)
        switch dimension {
        case .perRepoDaily:
            out += "date,repo,events,input_tokens,output_tokens,cache_read_tokens,cache_creation_tokens,cost_usd\n"
            let rows = try await db.perRepoDaily(since: range.start, until: range.end)
            for r in rows {
                out += "\(r.date),\(csvEscape(r.repo)),\(r.events),\(r.input),\(r.output),\(r.cacheRead),\(r.cacheCreation),\(String(format: "%.4f", r.cost))\n"
            }
        case .perToolDaily, .perModelDaily, .rawEvents:
            out += "" // landed in Tasks 3, 4, 5
        }
        return out
    }

    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    private func csvHeader(range: DateInterval, dimension: ExportDimension) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return """
            # claudegrain export — primaryTool attribution, public price-table cost estimate.
            # Not the Anthropic billing source of truth. Generated \(Self.timestampNow()).
            # Range: \(formatter.string(from: range.start)) → \(formatter.string(from: range.end))  Dimension: \(dimension.rawValue)

            """
    }

    private func jsonPayload(range: DateInterval, dimension: ExportDimension) async throws -> String {
        return "{}"
    }

    static func timestampNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
