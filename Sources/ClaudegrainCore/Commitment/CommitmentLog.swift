import Foundation

public struct Commitment: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case open, markedPaused, ignored
    }

    public let id: UUID
    public let repo: String
    public let triggeredAt: Date
    public let dailyOverspendUSD: Double
    public var status: Status

    public init(id: UUID, repo: String, triggeredAt: Date, dailyOverspendUSD: Double, status: Status) {
        self.id = id
        self.repo = repo
        self.triggeredAt = triggeredAt
        self.dailyOverspendUSD = dailyOverspendUSD
        self.status = status
    }
}

@MainActor
public final class CommitmentLog: ObservableObject {
    public static let defaultURL: URL = {
        let support = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support
            .appendingPathComponent("claudegrain", isDirectory: true)
            .appendingPathComponent("commitments.json")
    }()

    @Published public private(set) var entries: [Commitment] = []

    private let url: URL

    public init(url: URL = CommitmentLog.defaultURL) {
        self.url = url
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.entries = Self.load(from: url)
    }

    public func record(_ commitment: Commitment) {
        entries.append(commitment)
        save()
    }

    public func update(id: UUID, status: Commitment.Status) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].status = status
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func load(from url: URL) -> [Commitment] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Commitment].self, from: data)) ?? []
    }
}
