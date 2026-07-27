import Foundation

public struct SharedUsageSnapshot: Codable, Equatable, Sendable {
  public let usedPercent: Double
  public let resetsAt: Date?
  public let planType: String?
  public let limitName: String?
  public let updatedAt: Date
  public let languageCode: String?

  public init(
    usedPercent: Double,
    resetsAt: Date?,
    planType: String?,
    limitName: String?,
    updatedAt: Date,
    languageCode: String? = nil
  ) {
    self.usedPercent = min(100, max(0, usedPercent))
    self.resetsAt = resetsAt
    self.planType = planType
    self.limitName = limitName
    self.updatedAt = updatedAt
    self.languageCode = languageCode
  }

  public var remainingPercent: Double {
    max(0, 100 - usedPercent)
  }

  public func isStale(
    relativeTo date: Date = Date(),
    maxAge: TimeInterval = 15 * 60
  ) -> Bool {
    date.timeIntervalSince(updatedAt) > maxAge
  }
}

public enum SharedUsageConfiguration {
  public static let widgetKind = "io.cmmuu.codex-usage-bar.usage-widget"
  public static let fallbackAppGroupIdentifier =
    "group.io.cmmuu.codex-usage-bar"

  public static func appGroupIdentifier(
    bundle: Bundle = .main
  ) -> String {
    guard
      let value = bundle.object(
        forInfoDictionaryKey: "CodexUsageAppGroupIdentifier"
      ) as? String,
      !value.isEmpty,
      !value.contains("$(")
    else {
      return fallbackAppGroupIdentifier
    }
    return value
  }
}
