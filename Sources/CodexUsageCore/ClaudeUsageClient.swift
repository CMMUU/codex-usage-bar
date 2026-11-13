import CodexUsageShared
import Foundation

public struct ClaudeUsageClient: Sendable {
  public init() {}

  public func fetchUsage() async throws -> SubscriptionUsageDetails {
    try SubscriptionStatusLineCapture.load(for: .claude)
  }

  public static func decodeStatusLine(
    _ data: Data, observedAt: Date = Date()
  ) throws -> SubscriptionUsageDetails? {
    let payload = try SubscriptionJSON.object(data)
    guard let limits = payload["rate_limits"] as? SubscriptionJSON.Object else { return nil }
    // The official status line supplies these windows for claude.ai subscriptions.
    let windows: [(String, UsageQuotaKind)] = [("seven_day", .weekly), ("five_hour", .fiveHour)]
    let quotas = windows.compactMap { key, kind -> SubscriptionQuota? in
      guard let row = limits[key] as? SubscriptionJSON.Object,
        let used = SubscriptionJSON.number(row["used_percentage"]), (0...100).contains(used)
      else { return nil }
      return SubscriptionQuota(
        id: kind.rawValue, kind: kind, unit: .percent, used: used,
        resetsAt: SubscriptionJSON.date(row["resets_at"]))
    }
    guard !quotas.isEmpty else { return nil }
    return SubscriptionUsageDetails(subscription: .claude, quotas: quotas, observedAt: observedAt)
  }
}
