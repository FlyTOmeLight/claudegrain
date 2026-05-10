import Foundation

public enum OAuthUsageError: Error, LocalizedError {
    case http(status: Int, body: String)
    /// 429 with the server-suggested wait. Distinct from `.http` so the
    /// coordinator can honor a real Retry-After value instead of the prior
    /// hard-coded 60-second guess that fueled retry storms when Anthropic
    /// asked for longer.
    case rateLimited(retryAfter: TimeInterval?, body: String)
    case decoding(String)
    case transport(Error)

    public var errorDescription: String? {
        switch self {
        case .http(let status, let body): return "HTTP \(status): \(body.prefix(200))"
        case .rateLimited(let after, let body):
            let suffix = after.map { " (retry after \(Int($0))s)" } ?? " (no Retry-After header)"
            return "HTTP 429\(suffix): \(body.prefix(200))"
        case .decoding(let msg): return "Decode failed: \(msg)"
        case .transport(let err): return "Transport: \(err.localizedDescription)"
        }
    }
}

/// Response from the undocumented `api.anthropic.com/api/oauth/usage` endpoint.
/// utilization is reported as 0-100 (a percent), NOT 0-1.
public struct OAuthUsageResponse: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public let utilization: Double
        public let resetsAt: Date?
    }
    public let fiveHour: Window?
    public let sevenDay: Window?
    public let sevenDaySonnet: Window?
}

public struct OAuthUsageClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let betaHeader = "oauth-2025-04-20"

    private let session: URLSession
    private let userAgent: String

    public init(session: URLSession = .shared, userAgent: String = "claudegrain/0.1") {
        self.session = session
        self.userAgent = userAgent
    }

    public func fetch(token: String) async throws -> OAuthUsageResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OAuthUsageError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OAuthUsageError.http(status: -1, body: "non-HTTP response")
        }
        if http.statusCode == 429 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OAuthUsageError.rateLimited(
                retryAfter: Self.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After")),
                body: body
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OAuthUsageError.http(status: http.statusCode, body: body)
        }
        return try Self.decode(data: data)
    }

    /// HTTP `Retry-After` header parser. Per RFC 7231 the value is either
    /// a delta-seconds integer or an HTTP-date. Returns the seconds-from-now
    /// equivalent, or nil if the header is absent or malformed.
    static func parseRetryAfter(_ raw: String?, now: Date = Date()) -> TimeInterval? {
        guard let raw, !raw.isEmpty else { return nil }
        if let seconds = Double(raw.trimmingCharacters(in: .whitespaces)) {
            return max(0, seconds)
        }
        // HTTP-date forms — IMF-fixdate, RFC-850, asctime. DateFormatter
        // covers the canonical IMF-fixdate; the others are uncommon in
        // practice for modern APIs.
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = fmt.date(from: raw) {
            return max(0, date.timeIntervalSince(now))
        }
        return nil
    }

    static func decode(data: Data) throws -> OAuthUsageResponse {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthUsageError.decoding("not a JSON object")
        }
        return OAuthUsageResponse(
            fiveHour: window(from: object["five_hour"]),
            sevenDay: window(from: object["seven_day"]),
            sevenDaySonnet: window(from: object["seven_day_sonnet"] ?? object["sonnet_only"])
        )
    }

    static func window(from raw: Any?) -> OAuthUsageResponse.Window? {
        guard let dict = raw as? [String: Any] else { return nil }
        let util = dict["utilization"] as? Double
            ?? (dict["utilization"] as? Int).map(Double.init)
            ?? 0
        return .init(utilization: util, resetsAt: parseDate(dict["resets_at"]))
    }

    static func parseDate(_ raw: Any?) -> Date? {
        guard let str = raw as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: str)
        }()
    }
}

public extension OAuthUsageResponse {
    /// Convert the OAuth response (utilization in 0-100) into the app's snapshot (fraction 0-1).
    var sessionSnapshot: SessionBlockSnapshot? {
        guard let fiveHour else { return nil }
        let resets = fiveHour.resetsAt ?? Date().addingTimeInterval(5 * 3600)
        let started = resets.addingTimeInterval(-5 * 3600)
        return SessionBlockSnapshot(
            startedAt: started,
            resetsAt: resets,
            usedFraction: fiveHour.utilization / 100.0,
            totalTokens: 0
        )
    }

    var weeklySnapshot: WeeklyUsageSnapshot? {
        guard let sevenDay else { return nil }
        let resets = sevenDay.resetsAt ?? Date().addingTimeInterval(7 * 86400)
        return WeeklyUsageSnapshot(
            usedFraction: sevenDay.utilization / 100.0,
            resetsAt: resets
        )
    }
}
