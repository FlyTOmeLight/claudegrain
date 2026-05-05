import Foundation

public struct UsageEvent: Equatable, Sendable {
    public let timestamp: Date
    public let sessionId: String
    public let cwd: String?
    public let gitBranch: String?
    public let model: String
    /// All tool_use blocks in this turn, in order. Kept for auditing.
    public let tools: [String]
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    /// Anthropic message id from `message.id`. Used (with `requestId`) to dedupe
    /// the same assistant turn appearing in multiple jsonl files (sidechains, forks).
    public let messageId: String?
    /// Top-level `requestId` written by Claude Code per backend round-trip.
    public let requestId: String?

    public init(
        timestamp: Date,
        sessionId: String,
        cwd: String?,
        gitBranch: String?,
        model: String,
        tools: [String],
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int,
        messageId: String? = nil,
        requestId: String? = nil
    ) {
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.model = model
        self.tools = tools
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.messageId = messageId
        self.requestId = requestId
    }

    /// Stable cross-file dedup key. Same assistant turn = same key, regardless of
    /// which transcript / sidechain file replays it. Nil when both ids missing.
    public var dedupKey: String? {
        guard let messageId, let requestId else { return nil }
        return "\(messageId)|\(requestId)"
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    /// Per ADR-0003: turn-level `usage` is attributed entirely to the first
    /// tool_use block. Returns nil for non-tool turns (final assistant text).
    public var primaryTool: String? { tools.first }

    /// Family grouping derived from `model`. ADR-0006: grouped in Swift, not SQL.
    public var modelFamily: ModelFamily { ModelFamily.parse(model) }

    /// MCP server when primaryTool is an MCP call, else nil.
    public var primaryMcpServer: String? {
        primaryTool?.mcpComponents()?.server
    }
}

public struct SessionBlockSnapshot: Sendable {
    public let startedAt: Date
    public let resetsAt: Date
    public let usedFraction: Double
    public let totalTokens: Int

    public init(startedAt: Date, resetsAt: Date, usedFraction: Double, totalTokens: Int) {
        self.startedAt = startedAt
        self.resetsAt = resetsAt
        self.usedFraction = usedFraction
        self.totalTokens = totalTokens
    }

    public var resetCountdown: String {
        let remaining = max(resetsAt.timeIntervalSinceNow, 0)
        let h = Int(remaining) / 3600
        let m = (Int(remaining) % 3600) / 60
        return String(format: "%dh %02dm", h, m)
    }
}

public struct WeeklyUsageSnapshot: Sendable {
    public let usedFraction: Double
    public let resetsAt: Date

    public init(usedFraction: Double, resetsAt: Date) {
        self.usedFraction = usedFraction
        self.resetsAt = resetsAt
    }

    public var resetLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: resetsAt)
    }
}

public struct DailyTotals: Sendable {
    public var costUSD: Double
    public var totalTokens: Int
    public var byModel: [String: Int]

    public init(costUSD: Double = 0, totalTokens: Int = 0, byModel: [String: Int] = [:]) {
        self.costUSD = costUSD
        self.totalTokens = totalTokens
        self.byModel = byModel
    }

    public static let zero = DailyTotals()
}

public struct RepoBreakdown: Identifiable, Sendable {
    public var id: String { fullCwd ?? repo }
    public let repo: String
    public let fullCwd: String?
    public let costUSD: Double
    public let totalTokens: Int
    /// 7-day spend trend in USD, oldest → newest. Populated by aggregator after top-repos fetch.
    public var spend7d: [Double]

    public init(repo: String, fullCwd: String? = nil, costUSD: Double, totalTokens: Int, spend7d: [Double] = []) {
        self.repo = repo
        self.fullCwd = fullCwd
        self.costUSD = costUSD
        self.totalTokens = totalTokens
        self.spend7d = spend7d
    }
}

public struct ToolBreakdown: Identifiable, Sendable {
    public var id: String { toolName }
    public let toolName: String
    public let mcpServer: String?
    public let costUSD: Double
    public let totalTokens: Int

    public init(toolName: String, mcpServer: String? = nil, costUSD: Double, totalTokens: Int) {
        self.toolName = toolName
        self.mcpServer = mcpServer
        self.costUSD = costUSD
        self.totalTokens = totalTokens
    }
}
