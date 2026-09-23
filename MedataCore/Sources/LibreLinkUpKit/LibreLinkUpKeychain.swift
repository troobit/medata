// Keychain storage for the LibreLinkUp credentials and auth session
// (specs/data/cgm-connect Req 3.1).
//
// Generic-password items with kSecAttrAccessibleAfterFirstUnlock so a
// background refresh — or the widget's own extension-side fetch — can read
// them on a locked device. Credentials never appear in event metadata;
// deleteAll() wipes both items (Req 6.2).
import Foundation
import Security

public struct LibreLinkUpKeychain: Sendable {

    // Shared keychain access group (glucose-lock-widget Decision 16): the app
    // writes these items and the MeDataWidgets extension reads them, so they
    // cannot live in either target's private group.
    //
    // The team-id prefix is part of the group string the keychain matches
    // against, so it is spelled out here — both targets declare the group as
    // `$(AppIdentifierPrefix)rtob.MeData.shared`, which expands to the same
    // literal. The team id is already pinned in the pbxproj
    // (docs/agent-notes/widget-extension.md); a team change breaks signing
    // first, which is where it would be noticed.
    //
    // Before the first unlock since boot no item is readable at all; the widget
    // then renders the stored snapshot, an accepted edge (design.md).
    public static let accessGroup = "6G974YC4Z2.rtob.MeData.shared"

    private static let service = "com.medata.librelinkup"
    private static let credentialsAccount = "credentials"
    private static let sessionAccount = "session"

    // Nil disables the access-group attribute entirely, which is what the
    // MedataCore test host needs: an unentitled process asking for a group it
    // does not hold gets errSecMissingEntitlement on every call.
    private let accessGroup: String?

    public init(accessGroup: String? = LibreLinkUpKeychain.accessGroup) {
        self.accessGroup = accessGroup
    }

    public func saveCredentials(_ credentials: LibreLinkUpCredentials) throws {
        try save(try JSONEncoder().encode(credentials), account: Self.credentialsAccount)
    }

    public func credentials() -> LibreLinkUpCredentials? {
        read(account: Self.credentialsAccount)
            .flatMap { try? JSONDecoder().decode(LibreLinkUpCredentials.self, from: $0) }
    }

    public func saveSession(_ session: LibreLinkUpSession) {
        if let data = try? JSONEncoder().encode(session) {
            try? save(data, account: Self.sessionAccount)
        }
    }

    public func session() -> LibreLinkUpSession? {
        read(account: Self.sessionAccount)
            .flatMap { try? JSONDecoder().decode(LibreLinkUpSession.self, from: $0) }
    }

    public func deleteSession() {
        delete(account: Self.sessionAccount)
    }

    public func deleteAll() {
        delete(account: Self.credentialsAccount)
        delete(account: Self.sessionAccount)
    }

    private func query(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func save(_ data: Data, account: String) throws {
        SecItemDelete(query(account: account) as CFDictionary)
        var attributes = query(account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LibreLinkUpError.keychainFailure(status)
        }
    }

    private func read(account: String) -> Data? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private func delete(account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
    }
}
