import CodexUsageShared
import Foundation

public struct MiniMaxUsageClient: Sendable {
  private let credentials: SubscriptionCredentialStore

  public init(credentials: SubscriptionCredentialStore = SubscriptionCredentialStore()) {
    self.credentials = credentials
  }

  public func fetchUsage() async throws -> SubscriptionUsageDetails {
    guard let key = try credentials.load(for: .minimax) else {
      throw SubscriptionUsageError.notConnected
    }
    let url = URL(string: "https://www.minimax.cn/v1/token_plan/remains")!
    let data = try await SubscriptionHTTP.read(url, authorization: "Bearer \(key)")
    return try Self.decodeUsage(data)
  }

  public static func decodeUsage(
    _ data: Data, observedAt: Date = Date()
  ) throws -> SubscriptionUsageDetails {
    let payload = try SubscriptionJSON.object(data)
    guard let response = payload["base_resp"] as? SubscriptionJSON.Object,
      SubscriptionJSON.number(response["status_code"]) == 0
    else { throw SubscriptionUsageError.unavailable }
    guard let models = payload["model_remains"] as? [SubscriptionJSON.Object] else {
      throw SubscriptionUsageError.invalidResponse
    }
    let quotas = models.flatMap { model -> [SubscriptionQuota] in
      guard let name = model["model_name"] as? String, !name.isEmpty, !isOutsidePlan(model) else {
        return []
      }
      let startsAt = SubscriptionJSON.date(model["start_time"])
      let endsAt = SubscriptionJSON.date(model["end_time"])
      let hours = (endsAt?.timeIntervalSince(startsAt ?? .distantPast) ?? 0) / 3600
      let interval: UsageQuotaKind = hours == 5 ? .fiveHour : .unknown
      let shortLabel =
        (1...168).contains(hours) && hours.rounded() == hours
        ? "\(name) · \(Int(hours))h" : name
      return [
        quota(
          model, prefix: "current_interval", id: "\(name)-interval", label: shortLabel,
          kind: interval, reset: endsAt ?? resetAfter(model["remains_time"], from: observedAt)),
        quota(
          model, prefix: "current_weekly", id: "\(name)-weekly", label: "\(name) · 7d",
          kind: .weekly,
          reset: SubscriptionJSON.date(model["weekly_end_time"])
            ?? resetAfter(model["weekly_remains_time"], from: observedAt)),
      ]
    }
    return try SubscriptionJSON.details(for: .minimax, plan: nil, quotas: quotas, at: observedAt)
  }

  private static func isOutsidePlan(_ model: SubscriptionJSON.Object) -> Bool {
    SubscriptionJSON.number(model["current_interval_total_count"]) == 0
      && SubscriptionJSON.number(model["current_weekly_total_count"]) == 0
      && SubscriptionJSON.number(model["current_interval_status"]) == 3
      && SubscriptionJSON.number(model["current_weekly_status"]) == 3
  }

  private static func resetAfter(_ value: Any?, from observedAt: Date) -> Date? {
    guard let milliseconds = SubscriptionJSON.number(value),
      (1...31 * 86_400_000).contains(milliseconds)
    else { return nil }
    return observedAt.addingTimeInterval(milliseconds / 1000)
  }

  private static func quota(
    _ model: SubscriptionJSON.Object, prefix: String, id: String, label: String,
    kind: UsageQuotaKind, reset: Date?
  ) -> SubscriptionQuota {
    if kind == .weekly, SubscriptionJSON.number(model["\(prefix)_status"]) == 3 {
      return SubscriptionQuota(
        id: id, kind: kind, label: label, unit: .unspecified, resetsAt: reset, isUnlimited: true)
    }
    let total = SubscriptionJSON.number(model["\(prefix)_total_count"])
    let reportedCount = SubscriptionJSON.number(model["\(prefix)_usage_count"])
    let percent = SubscriptionJSON.number(model["\(prefix)_remaining_percent"]).flatMap {
      (0...100).contains($0) ? $0 : nil
    }
    if let total, total > 0, let reportedCount, (0...total).contains(reportedCount) {
      // MiniMax CLI treats the older count as remaining. New responses can use
      // either convention, disambiguated by the explicitly named percentage.
      let reportedPercent = reportedCount / total * 100
      let asRemaining = percent.map { abs($0 - reportedPercent) } ?? 0
      let asUsed = percent.map { abs($0 - (100 - reportedPercent)) } ?? 101
      if min(asRemaining, asUsed) <= 1 {
        let remaining = asRemaining <= asUsed ? reportedCount : total - reportedCount
        return SubscriptionQuota(
          id: id, kind: kind, label: label, unit: .unspecified, remaining: remaining,
          limit: total, resetsAt: reset)
      }
    }
    if let percent {
      return SubscriptionQuota(
        id: id, kind: kind, label: label, unit: .percent, remaining: percent, resetsAt: reset)
    }
    return SubscriptionQuota(
      id: id, kind: kind, label: label, unit: .unspecified,
      limit: total.flatMap { $0 > 0 ? $0 : nil }, resetsAt: reset)
  }
}
