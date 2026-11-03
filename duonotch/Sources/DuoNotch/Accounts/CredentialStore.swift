import Foundation
import Security
import CryptoKit
import DuoNotchShared

/// The OAuth record Claude Code keeps for a `claude.ai` login.
struct OAuthCredentials: Decodable {
    let accessToken: String
    let refreshToken: String?
    /// Milliseconds since the epoch.
    let expiresAt: Double?
    let subscriptionType: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date(timeIntervalSince1970: expiresAt / 1000) < Date()
    }
}

private struct CredentialsFile: Decodable {
    let claudeAiOauth: OAuthCredentials?
}

enum CredentialError: Error, LocalizedError {
    case notFound(searched: [String])
    case keychainDenied(OSStatus)
    case malformed

    var errorDescription: String? {
        switch self {
        case .notFound(let searched):
            return "No Claude Code login found (looked in \(searched.joined(separator: ", ")))"
        case .keychainDenied(let status):
            return "Keychain access denied (status \(status)). Click Allow on the keychain prompt."
        case .malformed:
            return "Credentials found but could not be parsed"
        }
    }
}

/// Reads – never writes, never refreshes – the token Claude Code stored.
enum CredentialStore {
    static let keychainServiceBase = "Claude Code-credentials"

    static func load(for account: Account) -> Result<OAuthCredentials, CredentialError> {
        var searched: [String] = []

        // 1. A credentials file inside the config directory (what Claude
        //    Code writes on platforms without a keychain; some people copy
        //    one onto their Mac too).
        let file = URL(fileURLWithPath: account.configDir).appendingPathComponent(".credentials.json")
        searched.append(file.path)
        if let data = try? Data(contentsOf: file) {
            if let creds = decode(data) { return .success(creds) }
            return .failure(.malformed)
        }

        // 2. The login keychain.
        for service in keychainServiceCandidates(for: account) {
            searched.append("keychain:\(service)")
            switch readKeychain(service: service) {
            case .success(let data?):
                if let creds = decode(data) { return .success(creds) }
                return .failure(.malformed)
            case .success(nil):
                continue
            case .failure(let status):
                return .failure(.keychainDenied(status))
            }
        }
        return .failure(.notFound(searched: searched))
    }

    /// Claude Code names the keychain item "Claude Code-credentials" for the
    /// default config directory. For a custom CLAUDE_CONFIG_DIR it appends a
    /// short hash of the directory path. We try the known spellings and let
    /// the user override the name in Settings if theirs differs.
    static func keychainServiceCandidates(for account: Account) -> [String] {
        var candidates: [String] = []
        if let override = account.keychainServiceOverride?.trimmingCharacters(in: .whitespaces), !override.isEmpty {
            candidates.append(override)
        }
        if account.isDefault {
            candidates.append(keychainServiceBase)
        } else {
            let digest = SHA256.hash(data: Data(account.configDir.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            candidates.append("\(keychainServiceBase)-\(hex.prefix(8))")
            candidates.append("\(keychainServiceBase)-\(hex)")
        }
        return candidates
    }

    /// Names of every "Claude Code…" keychain item. Reading attributes does
    /// not trigger a password prompt, so this is safe to show in Settings
    /// to help pick an override.
    static func allClaudeKeychainServices() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrService as String] as? String }
            .filter { $0.hasPrefix("Claude Code") }
            .sorted()
    }

    // MARK: - Private

    private static func decode(_ data: Data) -> OAuthCredentials? {
        guard let file = try? JSONDecoder().decode(CredentialsFile.self, from: data) else { return nil }
        return file.claudeAiOauth
    }

    private static func readKeychain(service: String) -> Result<Data?, OSStatus> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data { return .success(data) }
        if status == errSecItemNotFound { return .success(nil) }
        return .failure(status)
    }
}
