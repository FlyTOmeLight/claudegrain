import XCTest
@testable import ClaudegrainCore

@MainActor
final class CommitmentLogTests: XCTestCase {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("commitments-\(UUID().uuidString).json")
    }

    func testRecordAndPersist() throws {
        let url = tempURL()
        let log1 = CommitmentLog(url: url)
        log1.record(Commitment(
            id: UUID(), repo: "/a", triggeredAt: Date(),
            dailyOverspendUSD: 12.0, status: .open
        ))
        XCTAssertEqual(log1.entries.count, 1)

        let log2 = CommitmentLog(url: url)
        XCTAssertEqual(log2.entries.count, 1)
        XCTAssertEqual(log2.entries.first?.repo, "/a")
    }

    func testUpdateStatus() {
        let url = tempURL()
        let log = CommitmentLog(url: url)
        let id = UUID()
        log.record(Commitment(id: id, repo: "/a", triggeredAt: Date(),
                              dailyOverspendUSD: 5.0, status: .open))
        log.update(id: id, status: .markedPaused)
        XCTAssertEqual(log.entries.first?.status, .markedPaused)
    }

    func testCorruptedFileRecoversAsEmpty() throws {
        let url = tempURL()
        try "bogus json {{{".write(to: url, atomically: true, encoding: .utf8)
        let log = CommitmentLog(url: url)
        XCTAssertTrue(log.entries.isEmpty)
    }
}
