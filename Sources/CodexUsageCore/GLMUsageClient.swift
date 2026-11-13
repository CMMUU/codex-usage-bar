import CodexUsageShared
import Foundation

public struct GLMUsageClient: Sendable {
  private let credentials: SubscriptionCredentialStore

  public init(credentials: SubscriptionCredentialStore = SubscriptionCredentialStore()) {
    self.credentials = credentials
  }

  public func fetchUsage() async throws -> SubscriptionUsageDetails {
    guard let key = try credentials.load(for: .glm) else {
      throw SubscriptionUsageError.notConnected
    }
    let url = URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!
    let data = try await SubscriptionHTTP.read(url, authorization: key)
    return try Self.decodeUsage(data)
  }

  public static func decodeUsage(
    _ data: Data, observedAt: Date = Date()
  ) throws -> SubscriptionUsageDetails {
    let response = try SubscriptionJSON.object(data)
    guard let payload = response["data"] as? SubscriptionJSON.Object,
      let limits = payload["limits"] as? [SubscriptionJSON.Object]
    else { throw SubscriptionUsageError.invalidResponse }

    let quotas = limits.compactMap { row -> SubscriptionQuota? in
      guard let type = row["type"] as? String else { return nil }
      let unit = SubscriptionJSON.number(row["unit"])
      let duration = SubscriptionJSON.number(row["number"])
      let kind: UsageQuotaKind
      switch (unit, duration) {
      case (3, 5): kind = .fiveHour
      case (6, 1): kind = .weekly
      case (5, 1): kind = .monthly
      case (nil, nil) where type == "TOKENS_LIMIT": kind = .fiveHour
      case (nil, nil) where type == "TIME_LIMIT": kind = .monthly
      default: kind = .unknown
      }
      let id =
        "\(type)-\(unit.map(String.init(describing:)) ?? "-")-\(duration.map(String.init(describing:)) ?? "-")"
      let reset = SubscriptionJSON.date(row["nextResetTime"])
      let usedPercent = SubscriptionJSON.number(row["percentage"])
      let used = SubscriptionJSON.amount(row["currentValue"])
      let total = SubscriptionJSON.amount(row["usage"])
      let remaining = SubscriptionJSON.amount(row["remaining"])
      switch type {
      case "TOKENS_LIMIT":
        return SubscriptionQuota(
          id: id, kind: kind, unit: .percent, used: usedPercent, resetsAt: reset)
      case "TIME_LIMIT", "CREDIT_LIMIT":
        let isMCP = type == "TIME_LIMIT"
        let label = isMCP ? "MCP" : nil
        if used != nil || remaining != nil {
          return SubscriptionQuota(
            id: id, kind: kind, label: label, unit: isMCP ? .requests : .credits,
            used: used, remaining: remaining, limit: total, resetsAt: reset)
        }
        return SubscriptionQuota(
          id: id, kind: kind, label: label, unit: .percent, used: usedPercent,
          resetsAt: reset)
      default:
        return nil
      }
    }
    let order: [UsageQuotaKind] = [.weekly, .fiveHour, .monthly, .unknown]
    return try SubscriptionJSON.details(
      for: .glm, plan: payload["level"] as? String,
      quotas: order.flatMap { kind in quotas.filter { $0.kind == kind } }, at: observedAt)
  }
}
