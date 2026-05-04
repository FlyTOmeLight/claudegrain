import Foundation
import ClaudegrainCore

// End-to-end spike: real keychain → real /oauth/usage → real jsonl → SQLite → aggregations.
// Run with `swift run claudegrain-spike` after Claude Code has been used at least once.

@main
struct Spike {
    static func main() async {
        print("==========  claudegrain spike  ==========")
        await checkOAuth()
        await checkJSONL()
        print("=========================================")
    }

    static func checkOAuth() async {
        print("\n[1] Keychain → access token")
        let reader = KeychainTokenReader()
        let token: String
        do {
            token = try reader.readAccessToken()
            let masked = String(token.prefix(8)) + "…(\(token.count) chars)"
            print("    ✓ token: \(masked)")
        } catch {
            print("    ✗ \(error.localizedDescription)")
            print("    skipping API call.")
            return
        }

        print("\n[2] GET api.anthropic.com/api/oauth/usage")
        let client = OAuthUsageClient()
        do {
            let resp = try await client.fetch(token: token)
            if let s = resp.fiveHour {
                print("    ✓ 5h: \(String(format: "%.1f", s.utilization))% used, resets \(s.resetsAt.map { String(describing: $0) } ?? "?")")
            }
            if let w = resp.sevenDay {
                print("    ✓ 7d: \(String(format: "%.1f", w.utilization))% used, resets \(w.resetsAt.map { String(describing: $0) } ?? "?")")
            }
            if let s = resp.sevenDaySonnet {
                print("    ✓ sonnet 7d: \(String(format: "%.1f", s.utilization))%")
            }
        } catch {
            print("    ✗ \(error.localizedDescription)")
        }
    }

    static func checkJSONL() async {
        print("\n[3] Scan ~/.claude/projects → SQLite")
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard let enumerator = FileManager.default.enumerator(
            at: projects,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("    ✗ cannot list \(projects.path)")
            return
        }

        let parser = JSONLParser()
        let reader = JSONLReader()
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudegrain-spike-\(UUID()).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let db: EventsDatabase
        do {
            db = try EventsDatabase(url: dbURL)
        } catch {
            print("    ✗ open db: \(error)")
            return
        }

        var fileCount = 0
        var eventCount = 0
        var totalCost = 0.0
        let startedAt = Date()
        let cutoff = Date().addingTimeInterval(-7 * 86400) // last 7 days only for spike speed

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            fileCount += 1
            // Skip files older than 7 days for spike speed.
            if let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               mtime < cutoff {
                continue
            }
            do {
                let (lines, cursor) = try reader.readNew(at: url, from: .init())
                let events = lines.compactMap { parser.parse(line: $0) }
                if events.isEmpty { continue }
                try await db.insertEvents(
                    events.filter { $0.timestamp >= cutoff },
                    from: url.path,
                    startingAt: 0,
                    cursor: cursor
                )
                eventCount += events.count
                for e in events { totalCost += CostCalculator.cost(for: e) }
            } catch {
                continue
            }
        }
        print("    ✓ scanned \(fileCount) jsonl files, \(eventCount) assistant events, $\(String(format: "%.2f", totalCost)) total cost (last 7d)")
        print("    elapsed: \(String(format: "%.2f", Date().timeIntervalSince(startedAt)))s")

        print("\n[4] Aggregations (today)")
        do {
            let totals = try await db.dailyTotals(on: Date())
            print("    today: $\(String(format: "%.2f", totals.costUSD)), \(totals.totalTokens) tokens, models: \(totals.byModel.count)")
            for (m, t) in totals.byModel.sorted(by: { $0.value > $1.value }) {
                print("      \(m): \(t) tokens")
            }
            let repos = try await db.topRepos(on: Date())
            print("    top repos:")
            for r in repos { print("      \(r.repo): $\(String(format: "%.2f", r.costUSD))") }
            let tools = try await db.topTools(on: Date())
            print("    top tools:")
            for t in tools {
                let mcp = t.mcpServer.map { " (mcp:\($0))" } ?? ""
                print("      \(t.toolName)\(mcp): $\(String(format: "%.2f", t.costUSD))")
            }
            let cache = try await db.cacheHitRate(on: Date())
            print("    cache hit: \(String(format: "%.1f", cache * 100))%")
        } catch {
            print("    ✗ aggregation: \(error)")
        }
    }
}
