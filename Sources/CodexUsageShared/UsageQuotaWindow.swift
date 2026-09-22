import Foundation

/// The scope of a quota, independent of the model consuming it.
public enum UsageQuotaKind: String, Codable, Sendable {
  case monthly
  case weekly
  case fiveHour
  case unknown

  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }

  public var durationMinutes: Int {
    switch self {
    case .weekly: return 10_080
    case .fiveHour: return 300
    case .monthly, .unknown: return 0
    }
  }

  public func title(in language: AppLanguage, for subscription: UsageSubscription) -> String {
    let prefix = subscription == .kimi && (self == .weekly || self == .fiveHour) ? "Code · " : ""
    switch self {
    case .monthly: return language.text(.monthlyQuota)
    case .weekly: return prefix + language.text(.weeklyLimit)
    case .fiveHour: return prefix + language.text(.fiveHourLimit)
    case .unknown: return language.text(.windowUsed)
    }
  }

  public func shortTitle(in language: AppLanguage) -> String {
    switch self {
    case .monthly: return language == .simplifiedChinese ? "月" : "Month"
    case .weekly: return language == .simplifiedChinese ? "周" : "Week"
    case .fiveHour: return "5h"
    case .unknown: return language == .simplifiedChinese ? "窗口" : "Window"
    }
  }
}

public struct UsageQuotaWindow: Codable, Equatable, Identifiable, Sendable {
  public let kind: UsageQuotaKind
  public let usedPercent: Double
  public let resetsAt: Date?
  public var id: UsageQuotaKind { kind }
  public var remainingPercent: Double { max(0, 100 - usedPercent) }

  public init(kind: UsageQuotaKind, usedPercent: Double, resetsAt: Date?) {
    self.kind = kind
    self.usedPercent = min(100, max(0, usedPercent))
    self.resetsAt = resetsAt
  }
}
