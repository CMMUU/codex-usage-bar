import Foundation

public enum UsageSubscription: String, CaseIterable, Codable, Identifiable, Sendable {
  case codex
  case kimi
  case claude
  case antigravity
  case copilot
  case glm
  case minimax
  case bailian
  case volcengineArk = "volcengine-ark"

  public static let storageKey = "usageSubscription"

  public var id: String {
    rawValue
  }

  public var displayName: String {
    switch self {
    case .codex:
      return "Codex"
    case .kimi:
      return "Kimi"
    case .claude:
      return "Claude Code"
    case .antigravity:
      return "Google Antigravity"
    case .copilot:
      return "GitHub Copilot"
    case .glm:
      return "GLM Coding Plan"
    case .minimax:
      return "MiniMax"
    case .bailian:
      return "阿里云百炼"
    case .volcengineArk:
      return "火山方舟"
    }
  }

  public func displayName(in language: AppLanguage) -> String {
    switch (self, language) {
    case (.bailian, .english): return "Alibaba Model Studio"
    case (.volcengineArk, .english): return "Volcengine Ark"
    default: return displayName
    }
  }

  public var connection: UsageSubscriptionConnection {
    switch self {
    case .codex, .kimi: return .existing
    case .claude, .antigravity: return .statusLine
    case .copilot, .bailian, .volcengineArk: return .officialCLI
    case .glm, .minimax: return .apiKey
    }
  }

  public var usesWeeklyWindow: Bool {
    self == .codex
  }

  public static func resolve(_ storedValue: String?) -> UsageSubscription {
    recognized(storedValue) ?? .codex
  }

  /// Use the defaulting resolver for preferences, never for matching quota owners.
  public static func recognized(_ value: String?) -> UsageSubscription? {
    if value == "k3" { return .kimi }
    return value.flatMap(UsageSubscription.init(rawValue:))
  }

  public init(from decoder: Decoder) throws {
    self = Self.resolve(try decoder.singleValueContainer().decode(String.self))
  }
}

public enum UsageSubscriptionConnection: Sendable {
  case existing
  case statusLine
  case officialCLI
  case apiKey
}
