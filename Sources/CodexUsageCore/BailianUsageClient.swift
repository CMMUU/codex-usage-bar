import CodexUsageShared
import Foundation

public struct BailianUsageClient: Sendable {
  public init() {}

  public func fetchUsage() async throws -> SubscriptionUsageDetails {
    let data = try await SubscriptionCLI.run("bl", ["usage", "coding-plan", "--output", "json"])
    return try Self.decodeUsage(data)
  }

  public static func decodeUsage(
    _ data: Data, observedAt: Date = Date()
  ) throws -> SubscriptionUsageDetails {
    let payload = try SubscriptionJSON.object(data)
    let windows: [(String, UsageQuotaKind)] = [
      ("perBillMonth", .monthly), ("perWeek", .weekly), ("per5Hour", .fiveHour),
    ]
    let quotas = windows.compactMap { key, kind -> SubscriptionQuota? in
      guard let row = payload[key] as? SubscriptionJSON.Object else { return nil }
      return SubscriptionQuota(
        id: kind.rawValue, kind: kind, unit: .requests,
        used: SubscriptionJSON.number(row["usedQuota"]),
        limit: SubscriptionJSON.number(row["totalQuota"]),
        resetsAt: SubscriptionJSON.date(row["resetTime"]))
    }
    return try SubscriptionJSON.details(
      for: .bailian, plan: payload["instanceType"] as? String, quotas: quotas, at: observedAt)
  }
}
