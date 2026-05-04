import Foundation

public enum KeychainTokenError: Error, LocalizedError {
    case securityCommandFailed(stderr: String, exitCode: Int32)
    case notLoggedIn
    case malformedCredential(availableKeys: String)

    public var errorDescription: String? {
        switch self {
        case .securityCommandFailed(let stderr, let exit):
            return "security CLI exit \(exit): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .notLoggedIn:
            return "No Claude Code OAuth token in keychain. Run `claude` to log in."
        case .malformedCredential(let keys):
            return "Keychain item missing claudeAiOauth.accessToken. Available: \(keys)"
        }
    }
}

/// Reads the Claude Code OAuth access token from the macOS login keychain.
///
/// Uses `/usr/bin/security` rather than `SecItemCopyMatching` for two reasons:
/// 1. `security` CLI is on the keychain ACL by default — no permission prompt.
/// 2. Mirrors the technique in richhickson/claudecodeusage which is known to work.
public struct KeychainTokenReader: Sendable {
    private let service: String
    private let executable: URL

    public init(service: String = "Claude Code-credentials",
                executable: URL = URL(fileURLWithPath: "/usr/bin/security")) {
        self.service = service
        self.executable = executable
    }

    public func readAccessToken() throws -> String {
        let raw = try runSecurity()
        return try parseAccessToken(from: raw)
    }

    func runSecurity() throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // security CLI exit 44 = item not in keychain.
            if process.terminationStatus == 44 {
                throw KeychainTokenError.notLoggedIn
            }
            throw KeychainTokenError.securityCommandFailed(stderr: err, exitCode: process.terminationStatus)
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func parseAccessToken(from raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KeychainTokenError.malformedCredential(availableKeys: "<not JSON>")
        }
        if let oauth = object["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            return token
        }
        let keys = object.keys.sorted().joined(separator: ", ")
        throw KeychainTokenError.malformedCredential(availableKeys: keys)
    }
}
