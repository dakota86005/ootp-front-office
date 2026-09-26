import Foundation
import LocalAuthentication
import Security

/// Where the provider keys handed to the server come from. They travel on the sidecar's stdin, never in its
/// environment (SWIFTUI_REBUILD.md section 5.1).
public protocol KeySource: Sendable {
    /// The keys by provider id (`anthropic`, `openai`, …); a provider without a key is simply absent. Async: a
    /// Keychain read may wait (on a prompt, at worst), and the caller must not be blocked by it.
    func keys() async -> [String: String]
}

/// No keys: the app works without any AI provider (D-001).
public struct NoKeys: KeySource {
    public init() {}
    public func keys() async -> [String: String] { [:] }
}

/// Keys given directly (tests, previews).
public struct FixedKeys: KeySource {
    public let values: [String: String]
    public init(_ values: [String: String]) { self.values = values }
    public func keys() async -> [String: String] { values }
}

/// The Mac Keychain's generic passwords under `com.dakotawise.pennant.apikeys`, one item per provider, the account
/// being the provider id (SWIFTUI_REBUILD.md section 7.6). This only reads: saving a key from Settings arrives with
/// N13. The read runs on a detached task, never on the caller's actor or the main thread. It is meant not to prompt
/// (`interactionNotAllowed`), but that setting governs the data-protection keychain; this query searches the login
/// keychain, where an item whose access list does not trust this build could still show the system's dialog. Which
/// keychain the keys live in is decided at N13, when the app first writes one.
public struct KeychainKeyStore: KeySource {
    public static let service = "com.dakotawise.pennant.apikeys"
    public let service: String

    public init(service: String = KeychainKeyStore.service) {
        self.service = service
    }

    public func keys() async -> [String: String] {
        let service = service
        return await Task.detached(priority: .userInitiated) { Self.read(service: service) }.value
    }

    static func read(service: String) -> [String: String] {
        let context = LAContext()
        context.interactionNotAllowed = true
        let list: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var found: CFTypeRef?
        guard SecItemCopyMatching(list as CFDictionary, &found) == errSecSuccess,
              let items = found as? [[String: Any]] else { return [:] }
        var keys: [String: String] = [:]
        for account in items.compactMap({ $0[kSecAttrAccount as String] as? String }) {
            let one: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true,
                kSecUseAuthenticationContext as String: context,
            ]
            var data: CFTypeRef?
            if SecItemCopyMatching(one as CFDictionary, &data) == errSecSuccess,
               let data = data as? Data,
               let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !key.isEmpty {
                keys[account] = key
            }
        }
        return keys
    }
}
