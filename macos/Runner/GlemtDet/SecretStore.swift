import Foundation
import Security

/// The macOS Keychain, reached through the app's existing method channel.
///
/// TeenBrain needs exactly one secret — the Anthropic API key — and reaching
/// the Keychain directly costs about eighty lines of Security framework. The
/// alternative, `flutter_secure_storage`, pulls in CocoaPods, and this project
/// deliberately has no CocoaPods step: a macOS build here is `flutter build`
/// and nothing else. That property is worth more than the eighty lines.
enum SecretStore {

  /// One keychain entry per app. Items are scoped to this service name.
  private static let service = "dk.teenbrain.secrets"

  private static func query(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  static func read(account: String) -> String? {
    var lookup = query(account)
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &item)
    guard status == errSecSuccess,
          let data = item as? Data,
          let value = String(data: data, encoding: .utf8),
          !value.isEmpty
    else {
      return nil
    }
    return value
  }

  /// Writes, replacing any existing value. Returns false only on a real
  /// Keychain failure — a locked keychain, or a denied prompt.
  @discardableResult
  static func write(account: String, value: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }

    // Update first: SecItemAdd fails with errSecDuplicateItem when the account
    // already exists, and an update keeps the item's existing ACL.
    let updateStatus = SecItemUpdate(
      query(account) as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if updateStatus == errSecSuccess { return true }

    guard updateStatus == errSecItemNotFound else { return false }

    var insert = query(account)
    insert[kSecValueData as String] = data
    // Available after the first unlock, and never synced to iCloud: this is a
    // key for this machine, not for the user's account.
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

    return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
  }

  /// Deleting something that is not there is a success, not an error.
  @discardableResult
  static func delete(account: String) -> Bool {
    let status = SecItemDelete(query(account) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}
