import Foundation

public enum UsageSubscription: String, CaseIterable, Codable, Identifiable, Sendable {
  case codex
  case k3

  public var id: String {
    rawValue
  }

  public var displayName: String {
    switch self {
    case .codex:
      return "Codex"
    case .k3:
      return "K3"
    }
  }

  public var usesWeeklyWindow: Bool {
    self == .codex
  }

  public static func resolve(_ storedValue: String?) -> UsageSubscription {
    guard let storedValue, let subscription = UsageSubscription(rawValue: storedValue) else {
      return .codex
    }
    return subscription
  }
}
