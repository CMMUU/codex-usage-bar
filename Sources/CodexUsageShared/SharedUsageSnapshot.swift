import Foundation

public struct SharedUsageSnapshot: Codable, Equatable, Sendable {
  public let usedPercent: Double
  public let resetsAt: Date?
  public let planType: String?
  public let limitName: String?
  public let updatedAt: Date
  public let windowDurationMinutes: Int?
  public let languageCode: String?
  public let subscriptionID: String?
  public let fiveHourUsedPercent: Double?
  public let fiveHourResetsAt: Date?

  public init(
    usedPercent: Double,
    resetsAt: Date?,
    planType: String?,
    limitName: String?,
    updatedAt: Date,
    windowDurationMinutes: Int? = nil,
    languageCode: String? = nil,
    subscriptionID: String? = nil,
    fiveHourUsedPercent: Double? = nil,
    fiveHourResetsAt: Date? = nil
  ) {
    self.usedPercent = min(100, max(0, usedPercent))
    self.resetsAt = resetsAt
    self.planType = planType
    self.limitName = limitName
    self.updatedAt = updatedAt
    self.windowDurationMinutes = windowDurationMinutes
    self.languageCode = languageCode
    self.subscriptionID = subscriptionID
    self.fiveHourUsedPercent = fiveHourUsedPercent.map {
      min(100, max(0, $0))
    }
    self.fiveHourResetsAt = fiveHourResetsAt
  }

  public var remainingPercent: Double {
    max(0, 100 - usedPercent)
  }

  public var fiveHourRemainingPercent: Double? {
    fiveHourUsedPercent.map { max(0, 100 - $0) }
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
