import CodexUsageShared
import Foundation
import LocalAuthentication
import Security

/// Only the containing app uses this service. Widget snapshots never include keys.
public struct SubscriptionCredentialStore: Sendable {
  public init() {}

  private func identity(for subscription: UsageSubscription) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "io.cmmuu.codex-usage-bar.subscription-key",
      kSecAttrAccount as String: subscription.rawValue,
      kSecAttrSynchronizable as String: false,
    ]
  }

  public func load(for subscription: UsageSubscription) throws -> String? {
    guard subscription.connection == .apiKey else { return nil }
    var query = identity(for: subscription)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let context = LAContext()
    context.interactionNotAllowed = true
    query[kSecUseAuthenticationContext as String] = context
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data,
      let key = String(data: data, encoding: .utf8)
    else { throw SubscriptionUsageError.keychain }
    return key
  }

  public func save(_ value: String, for subscription: UsageSubscription) throws {
    let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard subscription.connection == .apiKey, !key.isEmpty, key.utf8.count <= 4096,
      key.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
    else { throw SubscriptionUsageError.keychain }
    let query = identity(for: subscription)
    let secret = Data(key.utf8)
    let status = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: secret] as CFDictionary)
    if status == errSecSuccess { return }
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = secret
      if SecItemAdd(item as CFDictionary, nil) == errSecSuccess { return }
    }
    throw SubscriptionUsageError.keychain
  }

  public func remove(for subscription: UsageSubscription) throws {
    guard subscription.connection == .apiKey else { return }
    let status = SecItemDelete(identity(for: subscription) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw SubscriptionUsageError.keychain
    }
  }
}
