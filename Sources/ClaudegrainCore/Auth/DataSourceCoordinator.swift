import Foundation
import os.log

/// Implements the state machine described in docs/adr/0004-data-source-coordinator.md.
///
/// JSONL is *always* on (driven by `IngestActor`). This coordinator manages the
/// OAuth path lifecycle: it produces an `AsyncStream<RateLimitSnapshot>` of session +
/// weekly snapshots when the OAuth path is live, and switches the source label
/// when the path degrades.
public actor DataSourceCoordinator {
    public enum State: Equatable, Sendable {
        case checking
        case oauthLive
        case oauthBackoff(until: Date)
        case oauthAuthError
        case jsonlOnly
        case oauthDeprecated
    }

    public struct Snapshot: Sendable {
        public let session: SessionBlockSnapshot?
        public let weekly: WeeklyUsageSnapshot?
        public let state: State
    }

    private let keychain: KeychainTokenReader
    private let client: OAuthUsageClient
    private let pollInterval: Duration
    private var state: State = .checking
    private var pollTask: Task<Void, Never>?
    private var continuation: AsyncStream<Snapshot>.Continuation?
    private var lastSnapshot: Snapshot?
    private static let logger = Logger(subsystem: "dev.claudegrain.menubar", category: "oauth")

    public init(
        keychain: KeychainTokenReader = .init(),
        client: OAuthUsageClient = .init(),
        pollInterval: Duration = .seconds(60)
    ) {
        self.keychain = keychain
        self.client = client
        self.pollInterval = pollInterval
    }

    public func start() -> AsyncStream<Snapshot> {
        let (stream, cont) = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = cont
        pollTask = Task { [weak self] in
            await self?.poll()
        }
        return stream
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        continuation?.finish()
        continuation = nil
    }

    public func currentState() -> State { state }

    /// Trigger an out-of-band tick. Polled loop continues independently.
    public func refreshNow() async {
        await tickOnce()
    }

    private func poll() async {
        while !Task.isCancelled {
            await tickOnce()
            let sleep = sleepDuration()
            try? await Task.sleep(for: sleep)
        }
    }

    private func tickOnce() async {
        let token: String
        do {
            token = try keychain.readAccessToken()
        } catch KeychainTokenError.notLoggedIn {
            Self.logger.info("OAuth tick: keychain has no token; degrading to JSONL")
            transition(to: .jsonlOnly)
            return
        } catch {
            Self.logger.error("OAuth tick: keychain read failed: \(String(describing: error), privacy: .public)")
            transition(to: .oauthAuthError)
            return
        }

        do {
            let resp = try await client.fetch(token: token)
            transition(to: .oauthLive)
            let snap = Snapshot(
                session: resp.sessionSnapshot,
                weekly: resp.weeklySnapshot,
                state: .oauthLive
            )
            lastSnapshot = snap
            continuation?.yield(snap)
        } catch let OAuthUsageError.rateLimited(retryAfter, body) {
            handleRateLimit(retryAfter: retryAfter, body: body)
        } catch let OAuthUsageError.http(status, body) {
            handleHTTPError(status: status, body: body)
        } catch let OAuthUsageError.transport(inner) {
            // Transient transport — keep state, but log so we can audit
            // recurring drops to JSONL after the fact.
            Self.logger.info("OAuth tick: transport error (state preserved): \(String(describing: inner), privacy: .public)")
        } catch {
            Self.logger.info("OAuth tick: unknown error (state preserved): \(String(describing: error), privacy: .public)")
        }
    }

    private func handleHTTPError(status: Int, body: String) {
        Self.logger.warning("OAuth HTTP \(status, privacy: .public): \(body.prefix(200), privacy: .public)")
        switch status {
        case 401, 403:
            transition(to: .oauthAuthError)
        case 500...599:
            // Stay in oauthLive so UI keeps last-good snapshot. Next tick retries.
            break
        default:
            // Schema mismatch / unknown — permanent jsonl-only.
            if body.lowercased().contains("html") || status == 404 {
                transition(to: .oauthDeprecated)
            }
        }
    }

    /// Honors the server's Retry-After header when present; falls back to
    /// 60s only when absent. The previous hard-coded 60s would burn through
    /// repeated 429s when Anthropic asked for a longer cool-down (observed
    /// 22+ minute degradations in production).
    private func handleRateLimit(retryAfter: TimeInterval?, body: String) {
        let wait = retryAfter ?? 60
        let retryAfterDesc = retryAfter == nil ? "missing" : String(Int(retryAfter!))
        Self.logger.warning("OAuth 429 — backoff \(Int(wait), privacy: .public)s (Retry-After \(retryAfterDesc, privacy: .public))")
        let until = Date().addingTimeInterval(wait)
        transition(to: .oauthBackoff(until: until))
    }

    private func sleepDuration() -> Duration {
        switch state {
        case .oauthBackoff(let until):
            let remaining = until.timeIntervalSinceNow
            return remaining > 0 ? .seconds(remaining) : pollInterval
        case .jsonlOnly, .oauthDeprecated:
            // Retry OAuth path after long gap in case user re-logs in or endpoint returns.
            return .seconds(300)
        default:
            return pollInterval
        }
    }

    private func transition(to next: State) {
        guard state != next else { return }
        Self.logger.notice("OAuth state: \(String(describing: self.state), privacy: .public) → \(String(describing: next), privacy: .public)")
        state = next
        if let last = lastSnapshot {
            continuation?.yield(.init(session: last.session, weekly: last.weekly, state: next))
        } else {
            continuation?.yield(.init(session: nil, weekly: nil, state: next))
        }
    }
}
