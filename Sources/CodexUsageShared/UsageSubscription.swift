import Foundation

public enum UsageSubscription: String, CaseIterable, Codable, Identifiable, Sendable {
  case codex
  case kimi

  public var id: String {
    rawValue
  }

  public var displayName: String {
    switch self {
    case .codex:
      return "Codex"
    case .kimi:
      return "Kimi"
    }
  }

  public var usesWeeklyWindow: Bool {
    self == .codex
  }

  public static func resolve(_ storedValue: String?) -> UsageSubscription {
    if storedValue == "k3" { return .kimi }
    guard let storedValue, let subscription = UsageSubscription(rawValue: storedValue) else {
      return .codex
    }
    return subscription
  }

  public init(from decoder: Decoder) throws {
    self = Self.resolve(try decoder.singleValueContainer().decode(String.self))
  }
}
