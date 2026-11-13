import CodexUsageShared
import Foundation

public struct VolcengineArkUsageClient: Sendable {
  public init() {}

  public func fetchUsage() async throws -> SubscriptionUsageDetails {
    let data = try await SubscriptionCLI.run(
      "arkcli", ["usage", "plan", "--product", "coding-plan", "--format", "json"])
    return try Self.decodeUsage(data)
  }

  public static func decodeUsage(
    _ data: Data, observedAt: Date = Date()
  ) throws -> SubscriptionUsageDetails {
    let payload = try SubscriptionJSON.object(data)
    guard let items = payload["items"] as? [SubscriptionJSON.Object] else {
      throw SubscriptionUsageError.invalidResponse
    }
    guard
      let item = items.first(where: {
        $0["product"] as? String == "coding-plan"
          && ($0["edition"] as? String ?? "personal") == "personal"
      })
    else { throw SubscriptionUsageError.unavailable }
    guard item["error"] == nil else { throw SubscriptionUsageError.unavailable }
    guard item["subscribed"] as? Bool == true,
      let periods = item["periods"] as? [SubscriptionJSON.Object]
    else { throw SubscriptionUsageError.unavailable }
    let quotas = ["monthly", "weekly", "session"].compactMap { key -> SubscriptionQuota? in
      guard let row = periods.first(where: { $0["label"] as? String == key }) else { return nil }
      return SubscriptionQuota(
        id: key, kind: SubscriptionJSON.quotaKind(key), unit: .percent,
        used: SubscriptionJSON.number(row["percent"]),
        resetsAt: SubscriptionJSON.date(row["reset_at"]))
    }
    return try SubscriptionJSON.details(
      for: .volcengineArk, plan: item["tier"] as? String, quotas: quotas,
      at: SubscriptionJSON.date(item["updated_at"]) ?? observedAt)
  }
}
