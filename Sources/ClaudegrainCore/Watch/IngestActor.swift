import Foundation

/// Owns the JSONL → SQLite ingestion pipeline. Off-main, single-writer.
/// Per ADR-0004 the JSONL path is always-on; this actor is its driver.
public actor IngestActor {
    public let db: EventsDatabase
    private let parser: JSONLParser
    private let reader: JSONLReader
    private let projectsRoot: URL
    private var fileWatcher: FileWatcher?
    private var snapshotContinuation: AsyncStream<Snapshot>.Continuation?
    private var publishTask: Task<Void, Never>?
    private var dirty = false

    public struct Snapshot: Sendable {
        public let today: DailyTotals
        public let topRepos: [RepoBreakdown]
        public let topTools: [ToolBreakdown]
        public let cacheHitRate: Double
        public let weekSpend: [Double]
    }

    public init(db: EventsDatabase, projectsRoot: URL? = nil) {
        self.db = db
        self.parser = JSONLParser()
        self.reader = JSONLReader()
        self.projectsRoot = projectsRoot ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    /// Returns an AsyncStream of throttled snapshots — caller should consume on the main actor.
    public func startStream() -> AsyncStream<Snapshot> {
        let (stream, continuation) = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.snapshotContinuation = continuation
        return stream
    }

    public func bootstrap(daysBack: Int = 7) async throws {
        let cutoff = Date().addingTimeInterval(-Double(daysBack) * 86400)
        let files = enumerateJSONL(modifiedAfter: cutoff)

        // Pre-filter: files whose on-disk size matches the persisted cursor have
        // nothing new to ingest. Repeat boots become near-instant once cursors are warm.
        let candidates = await filterUnseen(files: files)

        // Bounded concurrency. Disk reads + parsing can overlap; DB writes
        // serialize naturally inside the actor.
        try await withThrowingTaskGroup(of: Void.self) { group in
            let maxConcurrent = 6
            var inflight = 0
            var iterator = candidates.makeIterator()

            func enqueueNext() {
                guard let url = iterator.next() else { return }
                inflight += 1
                group.addTask { [weak self] in
                    try await self?.ingest(file: url)
                }
            }
            for _ in 0..<maxConcurrent { enqueueNext() }
            for try await _ in group {
                inflight -= 1
                enqueueNext()
            }
        }
        await publishSnapshotNow()
    }

    private func filterUnseen(files: [URL]) async -> [URL] {
        var keep: [URL] = []
        for url in files {
            let canonical = url.resolvingSymlinksInPath().path
            let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let size = (attrs[.size] as? UInt64) ?? 0
            if let cursor = try? await db.cursor(for: canonical),
               cursor.sizeAtLastRead == size && size > 0 {
                continue   // unchanged since last bootstrap
            }
            keep.append(url)
        }
        return keep
    }

    public func startWatching() async {
        let watcher = FileWatcher { [weak self] paths in
            Task { [weak self] in
                guard let self else { return }
                await self.handleChanged(paths: paths)
            }
        }
        watcher.start(paths: [projectsRoot.path])
        self.fileWatcher = watcher
        // Periodic publish (debounce). 750ms keeps UI responsive without thrashing.
        publishTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 750_000_000)
                await self?.publishIfDirty()
            }
        }
    }

    public func stop() async {
        fileWatcher?.stop()
        fileWatcher = nil
        publishTask?.cancel()
        publishTask = nil
        snapshotContinuation?.finish()
        snapshotContinuation = nil
    }

    /// Force a re-scan of recent JSONL + immediate snapshot publish. Wired to F5.
    public func refreshNow(daysBack: Int = 7) async {
        try? await bootstrap(daysBack: daysBack)
        await publishSnapshotNow()
    }

    private func handleChanged(paths: [String]) async {
        for path in paths where path.hasSuffix(".jsonl") {
            let url = URL(fileURLWithPath: path)
            try? await ingest(file: url)
        }
    }

    private func ingest(file url: URL) async throws {
        // Canonicalize via resolvingSymlinksInPath so /private/var ↔ /var resolve to the same key.
        let canonicalPath = url.resolvingSymlinksInPath().path
        let cursor = (try? await db.cursor(for: canonicalPath)) ?? .init()
        let (lines, newCursor) = try reader.readNew(at: url, from: cursor)
        if lines.isEmpty {
            if newCursor != cursor {
                try await db.insertEvents([], from: canonicalPath, startingAt: 0, cursor: newCursor)
            }
            return
        }
        let events = lines.compactMap { parser.parse(line: $0) }
        if events.isEmpty {
            try await db.insertEvents([], from: canonicalPath, startingAt: 0, cursor: newCursor)
            return
        }
        try await db.insertEvents(events, from: canonicalPath, startingAt: cursor.offset, cursor: newCursor)
        dirty = true
    }

    private func publishIfDirty() async {
        guard dirty else { return }
        dirty = false
        await publishSnapshotNow()
    }

    private func publishSnapshotNow() async {
        let now = Date()
        do {
            let totals = try await db.dailyTotals(on: now)
            var repos = try await db.topRepos(on: now)
            let tools = try await db.topTools(on: now)
            let cache = try await db.cacheHitRate(on: now)
            let weekSpend = try await db.costPerDay(days: 7, now: now)

            // Hydrate per-repo 7d trends so cost-row sparklines reflect real data.
            let cwds = repos.compactMap(\.fullCwd)
            if !cwds.isEmpty {
                let trends = try await db.costPerDayByRepo(days: 7, repos: cwds, now: now)
                repos = repos.map { r in
                    var copy = r
                    copy.spend7d = r.fullCwd.flatMap { trends[$0] } ?? r.spend7d
                    return copy
                }
            }

            snapshotContinuation?.yield(.init(
                today: totals,
                topRepos: repos,
                topTools: tools,
                cacheHitRate: cache,
                weekSpend: weekSpend
            ))
        } catch {
            // Silent: next publish tick will retry.
        }
    }

    private func enumerateJSONL(modifiedAfter cutoff: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            if let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               mtime < cutoff {
                continue
            }
            out.append(url)
        }
        return out
    }
}
