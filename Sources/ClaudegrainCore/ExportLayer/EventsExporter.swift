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
        case .perToolDaily:
            out += "date,tool,events,input_tokens,output_tokens,cost_usd\n"
            let rows = try await db.perToolDaily(since: range.start, until: range.end)
            for r in rows {
                out += "\(r.date),\(csvEscape(r.tool)),\(r.events),\(r.input),\(r.output),\(String(format: "%.4f", r.cost))\n"
            }
        case .perModelDaily:
            out += "date,model_family,model_id,events,input_tokens,output_tokens,cost_usd\n"
            let rows = try await db.perModelDaily(since: range.start, until: range.end)
            for r in rows {
                let fam = ModelFamily.parse(r.modelId)
                let famStr = String(describing: fam)   // "opus" / "sonnet" / "haiku" / "unknown"
                out += "\(r.date),\(famStr),\(csvEscape(r.modelId)),\(r.events),\(r.input),\(r.output),\(String(format: "%.4f", r.cost))\n"
            }
        case .rawEvents:
            out += "timestamp,session_id,repo,git_branch,model,primary_tool,input_tokens,output_tokens,cache_creation_tokens,cache_read_tokens,cost_usd\n"
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let rows = try await db.rawEventsInRange(since: range.start, until: range.end)
            for r in rows {
                let ts: Date = r["ts"] ?? Date()
                let inTok: Int64 = r["in_tok"] ?? 0
                let outTok: Int64 = r["out_tok"] ?? 0
                let cc: Int64 = r["cache_create_tok"] ?? 0
                let cr: Int64 = r["cache_read_tok"] ?? 0
                let cost: Double = r["cost_usd"] ?? 0
                let fields: [String] = [
                    iso.string(from: ts),
                    csvEscape(r["session_id"]   ?? ""),
                    csvEscape(r["cwd"]          ?? ""),
                    csvEscape(r["git_branch"]   ?? ""),
                    csvEscape(r["model"]        ?? ""),
                    csvEscape(r["primary_tool"] ?? ""),
                    String(inTok),
                    String(outTok),
                    String(cc),
                    String(cr),
                    String(format: "%.4f", cost),
                ]
                out += fields.joined(separator: ",") + "\n"
            }
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
