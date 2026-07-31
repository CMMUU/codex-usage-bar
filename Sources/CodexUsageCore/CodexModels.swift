import Foundation

struct RPCEnvelope<Result: Decodable & Sendable>: Decodable, Sendable {
  let id: Int?
  let result: Result?
  let error: RPCErrorPayload?
}

struct RPCErrorPayload: Decodable, Sendable, LocalizedError {
  let code: Int
  let message: String

  var errorDescription: String? {
    "Codex app-server 错误 \(code)：\(message)"
  }
}

struct AccountReadResult: Decodable, Sendable {
  let account: CodexAccount?
  let requiresOpenaiAuth: Bool
}

struct CodexAccount: Decodable, Sendable {
  let type: String
  let planType: String?
}

public struct RateLimitsReadResult: Decodable, Sendable {
  let rateLimits: CodexRateLimitSnapshot?
  let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
}

struct CodexRateLimitSnapshot: Decodable, Sendable {
  let limitId: String?
  let limitName: String?
  let planType: String?
  let primary: CodexRateLimitWindow?
  let secondary: CodexRateLimitWindow?
  let rateLimitReachedType: String?
}

struct CodexRateLimitWindow: Decodable, Sendable {
  let usedPercent: Double?
  let windowDurationMins: Int?
  let resetsAt: Int64?
}

public struct UsageSubWindow: Sendable, Equatable {
  public let usedPercent: Double
  public let windowDurationMinutes: Int
  public let resetsAt: Date?

  public init(
    usedPercent: Double,
    windowDurationMinutes: Int,
    resetsAt: Date?
  ) {
    self.usedPercent = usedPercent
    self.windowDurationMinutes = windowDurationMinutes
    self.resetsAt = resetsAt
  }

  public var remainingPercent: Double {
    max(0, 100 - usedPercent)
  }
}

public struct UsageSnapshot: Sendable, Equatable {
  public let usedPercent: Double
  public let windowDurationMinutes: Int
  public let resetsAt: Date?
  public let planType: String?
  public let limitName: String?
  public let reachedLimitType: String?
  public let fiveHourWindow: UsageSubWindow?

  public init(
    usedPercent: Double,
    windowDurationMinutes: Int,
    resetsAt: Date?,
    planType: String?,
    limitName: String?,
    reachedLimitType: String?,
    fiveHourWindow: UsageSubWindow? = nil
  ) {
    self.usedPercent = usedPercent
    self.windowDurationMinutes = windowDurationMinutes
    self.resetsAt = resetsAt
    self.planType = planType
    self.limitName = limitName
    self.reachedLimitType = reachedLimitType
    self.fiveHourWindow = fiveHourWindow
  }

  public var remainingPercent: Double {
    max(0, 100 - usedPercent)
  }
}

public enum UsageSelectionError: LocalizedError, Equatable {
  case noRateLimits
  case noWeeklyWindow
  case missingUsagePercent

  public var errorDescription: String? {
    switch self {
    case .noRateLimits:
      return "Codex 没有返回限额数据"
    case .noWeeklyWindow:
      return "Codex 返回了限额数据，但没有找到周限额窗口"
    case .missingUsagePercent:
      return "周限额数据缺少使用百分比"
    }
  }
}

public enum WeeklyUsageSelector {
  private static let weeklyWindowMinutes = 7 * 24 * 60
  private static let acceptedWindowRange = (6 * 24 * 60)...(8 * 24 * 60)
  private static let fiveHourWindowMinutes = 5 * 60
  private static let fiveHourWindowRange = (4 * 60)...(6 * 60)

  private struct Candidate {
    let snapshot: CodexRateLimitSnapshot
    let window: CodexRateLimitWindow
    let sourceName: String?
    let sourcePriority: Int
  }

  public static func select(
    from result: RateLimitsReadResult,
    accountPlanType: String?
  ) throws -> UsageSnapshot {
    var candidates: [Candidate] = []

    if let defaultSnapshot = result.rateLimits {
      appendWindows(
        from: defaultSnapshot,
        sourceName: defaultSnapshot.limitName ?? defaultSnapshot.limitId,
        sourcePriority: 0,
        to: &candidates
      )
    }

    for (key, snapshot) in (result.rateLimitsByLimitId ?? [:]).sorted(by: { $0.key < $1.key }) {
      let priority = key == "codex" ? 1 : 2
      appendWindows(
        from: snapshot,
        sourceName: snapshot.limitName ?? snapshot.limitId ?? key,
        sourcePriority: priority,
        to: &candidates
      )
    }

    guard !candidates.isEmpty else {
      throw UsageSelectionError.noRateLimits
    }

    let weeklyCandidates = candidates.filter {
      guard let duration = $0.window.windowDurationMins else {
        return false
      }
      return acceptedWindowRange.contains(duration)
    }

    guard let selected = weeklyCandidates.min(by: candidateSort) else {
      throw UsageSelectionError.noWeeklyWindow
    }
    guard let rawUsedPercent = selected.window.usedPercent else {
      throw UsageSelectionError.missingUsagePercent
    }

    let duration = selected.window.windowDurationMins ?? weeklyWindowMinutes
    let resetsAt = selected.window.resetsAt.map {
      Date(timeIntervalSince1970: TimeInterval($0))
    }

    return UsageSnapshot(
      usedPercent: min(100, max(0, rawUsedPercent)),
      windowDurationMinutes: duration,
      resetsAt: resetsAt,
      planType: selected.snapshot.planType ?? accountPlanType,
      limitName: selected.sourceName,
      reachedLimitType: selected.snapshot.rateLimitReachedType,
      fiveHourWindow: selectFiveHourWindow(from: candidates)
    )
  }

  private static func selectFiveHourWindow(
    from candidates: [Candidate]
  ) -> UsageSubWindow? {
    let fiveHourCandidates = candidates.filter {
      guard let duration = $0.window.windowDurationMins,
        $0.window.usedPercent != nil
      else {
        return false
      }
      return fiveHourWindowRange.contains(duration)
    }

    guard let selected = fiveHourCandidates.min(by: fiveHourSort),
      let rawUsedPercent = selected.window.usedPercent
    else {
      return nil
    }

    return UsageSubWindow(
      usedPercent: min(100, max(0, rawUsedPercent)),
      windowDurationMinutes: selected.window.windowDurationMins
        ?? fiveHourWindowMinutes,
      resetsAt: selected.window.resetsAt.map {
        Date(timeIntervalSince1970: TimeInterval($0))
      }
    )
  }

  private static func fiveHourSort(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
    let leftDistance = abs(
      (lhs.window.windowDurationMins ?? 0) - fiveHourWindowMinutes
    )
    let rightDistance = abs(
      (rhs.window.windowDurationMins ?? 0) - fiveHourWindowMinutes
    )
    if leftDistance != rightDistance {
      return leftDistance < rightDistance
    }
    return lhs.sourcePriority < rhs.sourcePriority
  }

  private static func appendWindows(
    from snapshot: CodexRateLimitSnapshot,
    sourceName: String?,
    sourcePriority: Int,
    to candidates: inout [Candidate]
  ) {
    if let primary = snapshot.primary {
      candidates.append(
        Candidate(
          snapshot: snapshot,
          window: primary,
          sourceName: sourceName,
          sourcePriority: sourcePriority
        )
      )
    }
    if let secondary = snapshot.secondary {
      candidates.append(
        Candidate(
          snapshot: snapshot,
          window: secondary,
          sourceName: sourceName,
          sourcePriority: sourcePriority
        )
      )
    }
  }

  private static func candidateSort(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
    let leftDistance = abs((lhs.window.windowDurationMins ?? 0) - weeklyWindowMinutes)
    let rightDistance = abs((rhs.window.windowDurationMins ?? 0) - weeklyWindowMinutes)
    if leftDistance != rightDistance {
      return leftDistance < rightDistance
    }
    return lhs.sourcePriority < rhs.sourcePriority
  }
}
