import CodexUsageShared
import Foundation

public struct CopilotUsageClient: Sendable {
  private let executable: URL?

  public init(executable: URL? = nil) {
    self.executable = executable
  }

  public func fetchUsage() async throws -> SubscriptionUsageDetails {
    let executable = try executable ?? SubscriptionCLI.locate("copilot")
    return try await Task.detached(priority: .utility) {
      let child = try SubscriptionCLIProcess(
        executable: executable, arguments: ["--headless", "--no-auto-update", "--stdio"],
        interactive: true)
      defer { child.close() }
      let connection = try child.rpc(id: 1, method: "connect")
      guard let version = SubscriptionJSON.number(connection["protocolVersion"]), version >= 3
      else {
        throw SubscriptionUsageError.invalidResponse
      }
      let auth = try child.rpc(id: 2, method: "auth.getStatus")
      guard auth["isAuthenticated"] as? Bool == true else {
        throw SubscriptionUsageError.notConnected
      }
      let result = try child.rpc(id: 3, method: "account.getQuota")
      return try Self.decode(result, observedAt: Date())
    }.value
  }

  public static func decodeUsage(
    _ data: Data, observedAt: Date = Date()
  ) throws -> SubscriptionUsageDetails {
    try decode(SubscriptionJSON.object(data), observedAt: observedAt)
  }

  private static func decode(
    _ payload: SubscriptionJSON.Object, observedAt: Date
  ) throws -> SubscriptionUsageDetails {
    guard let buckets = payload["quotaSnapshots"] as? [String: SubscriptionJSON.Object] else {
      throw SubscriptionUsageError.invalidResponse
    }
    let priority = ["premium_interactions", "chat", "completions"]
    let keys = priority + buckets.keys.filter { !priority.contains($0) }.sorted()
    let quotas = keys.compactMap { key -> SubscriptionQuota? in
      guard let row = buckets[key] else { return nil }
      let limit = SubscriptionJSON.number(row["entitlementRequests"])
      let used = SubscriptionJSON.amount(row["usedRequests"])
      let remainingPercent = SubscriptionJSON.number(row["remainingPercentage"])
      let unlimited = row["isUnlimitedEntitlement"] as? Bool == true || limit == -1
      let reset = SubscriptionJSON.date(row["resetDate"])
      let label = key.replacingOccurrences(of: "_", with: " ").capitalized

      if !unlimited, let remainingPercent, (0...100).contains(remainingPercent),
        used == nil || limit == nil || limit == 0
      {
        return SubscriptionQuota(
          id: key, label: label, unit: .percent, remaining: remainingPercent, resetsAt: reset)
      }
      return SubscriptionQuota(
        id: key, label: label, unit: .requests, used: used, limit: limit,
        resetsAt: reset, isUnlimited: unlimited)
    }
    return try SubscriptionJSON.details(for: .copilot, plan: nil, quotas: quotas, at: observedAt)
  }
}
