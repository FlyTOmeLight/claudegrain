import XCTest
@testable import ClaudegrainCore

final class ModelFamilyTests: XCTestCase {
    func testParsesOpus() {
        XCTAssertEqual(ModelFamily.parse("claude-opus-4-7"), .opus)
        XCTAssertEqual(ModelFamily.parse("claude-opus-4-6"), .opus)
        XCTAssertEqual(ModelFamily.parse("claude-3-opus-20240229"), .opus)
    }

    func testParsesSonnet() {
        XCTAssertEqual(ModelFamily.parse("claude-sonnet-4-6"), .sonnet)
        XCTAssertEqual(ModelFamily.parse("claude-3-5-sonnet-20240620"), .sonnet)
    }

    func testParsesHaiku() {
        XCTAssertEqual(ModelFamily.parse("claude-haiku-4-5-20251001"), .haiku)
        XCTAssertEqual(ModelFamily.parse("claude-3-haiku-20240307"), .haiku)
    }

    func testUnknownReturnsUnknown() {
        XCTAssertEqual(ModelFamily.parse(""), .unknown)
        XCTAssertEqual(ModelFamily.parse("gpt-4"), .unknown)
        XCTAssertEqual(ModelFamily.parse("claude-instant-1"), .unknown)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(ModelFamily.parse("CLAUDE-OPUS-4-7"), .opus)
    }
}
