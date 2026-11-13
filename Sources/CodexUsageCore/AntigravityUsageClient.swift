import CodexUsageShared
import Foundation

public struct AntigravityUsageClient: Sendable {
  public init() {}

  public func fetchUsage() async throws -> SubscriptionUsageDetails {
    try SubscriptionStatusLineCapture.load(for: .antigravity)
  }

  public static func decodeStatusLine(
    _ data: Data, observedAt: Date = Date()
  ) throws -> SubscriptionUsageDetails? {
    let payload = try SubscriptionJSON.object(data)
    guard payload["product"] as? String == "antigravity",
      let buckets = payload["quota"] as? [String: SubscriptionJSON.Object]
    else { return nil }

    let quotas = buckets.keys.sorted().compactMap { key -> SubscriptionQuota? in
      guard let bucket = buckets[key], bucket["disabled"] as? Bool != true else { return nil }
      let fraction = SubscriptionJSON.number(bucket["remaining_fraction"]).flatMap {
        (0...1).contains($0) ? $0 : nil
      }
      let remaining =
        fraction.map { $0 * 100 } ?? SubscriptionJSON.number(bucket["remaining_amount"])
      let countdown = SubscriptionJSON.number(bucket["reset_in_seconds"]).flatMap {
        (0...(31 * 24 * 60 * 60)).contains($0) ? observedAt.addingTimeInterval($0) : nil
      }
      return SubscriptionQuota(
        id: key, kind: SubscriptionJSON.quotaKind(key.split(separator: "-").last.map(String.init)),
        label: key, unit: fraction == nil ? .unspecified : .percent, remaining: remaining,
        resetsAt: SubscriptionJSON.date(bucket["reset_time"]) ?? countdown)
    }
    let details = SubscriptionUsageDetails(
      subscription: .antigravity, planName: payload["plan_tier"] as? String, quotas: quotas,
      observedAt: observedAt)
    return details.quotas.isEmpty ? nil : details
  }
}
