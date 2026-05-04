import XCTest
@testable import ClaudegrainCore

final class AuthTests: XCTestCase {
    func testParseAccessTokenFromCredentialBlob() throws {
        let reader = KeychainTokenReader()
        let blob = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"rt"}}"#
        let token = try reader.parseAccessToken(from: blob)
        XCTAssertEqual(token, "sk-ant-oat01-abc")
    }

    func testParseAccessTokenMissingOAuthKey() {
        let reader = KeychainTokenReader()
        let blob = #"{"someOtherKey":{"value":"x"}}"#
        XCTAssertThrowsError(try reader.parseAccessToken(from: blob)) { error in
            guard case KeychainTokenError.malformedCredential(let keys) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(keys.contains("someOtherKey"))
        }
    }

    func testParseAccessTokenMalformed() {
        let reader = KeychainTokenReader()
        XCTAssertThrowsError(try reader.parseAccessToken(from: "not-json"))
    }

    func testDecodeOAuthUsageResponse() throws {
        let json = """
        {
          "five_hour": {"utilization": 67.5, "resets_at": "2026-05-04T18:00:00Z"},
          "seven_day": {"utilization": 32, "resets_at": "2026-05-11T00:00:00Z"},
          "seven_day_sonnet": {"utilization": 12.0, "resets_at": "2026-05-11T00:00:00Z"},
          "extra_usage": {"is_enabled": false}
        }
        """.data(using: .utf8)!

        let parsed = try OAuthUsageClient.decode(data: json)
        XCTAssertEqual(parsed.fiveHour?.utilization, 67.5)
        XCTAssertNotNil(parsed.fiveHour?.resetsAt)
        XCTAssertEqual(parsed.sevenDay?.utilization, 32.0)
        XCTAssertEqual(parsed.sevenDaySonnet?.utilization, 12.0)
    }

    func testSnapshotConvertsPercentToFraction() throws {
        let json = """
        {"five_hour": {"utilization": 75, "resets_at": "2099-01-01T00:00:00Z"},
         "seven_day": {"utilization": 50, "resets_at": "2099-01-08T00:00:00Z"}}
        """.data(using: .utf8)!
        let parsed = try OAuthUsageClient.decode(data: json)

        let session = try XCTUnwrap(parsed.sessionSnapshot)
        XCTAssertEqual(session.usedFraction, 0.75, accuracy: 0.0001)
        let weekly = try XCTUnwrap(parsed.weeklySnapshot)
        XCTAssertEqual(weekly.usedFraction, 0.5, accuracy: 0.0001)
    }

    func testDecodeFallsBackToSonnetOnly() throws {
        let json = #"{"five_hour": {"utilization": 0}, "sonnet_only": {"utilization": 20}}"#.data(using: .utf8)!
        let parsed = try OAuthUsageClient.decode(data: json)
        XCTAssertEqual(parsed.sevenDaySonnet?.utilization, 20.0)
    }
}
