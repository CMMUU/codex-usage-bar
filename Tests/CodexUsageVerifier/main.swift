import CodexUsageCore
import CodexUsageShared
import Darwin
import Foundation

@main
struct CodexUsageVerifier {
  static func main() async {
    do {
      try runUnitChecks()
      if CommandLine.arguments.contains("--integration") {
        try await runIntegrationCheck()
      }
      print("验证完成：全部通过")
    } catch {
      fputs("验证失败：\(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }

  private static func runUnitChecks() throws {
    let primaryWeekly = try decodeRateLimits(
      """
      {
        "rateLimits": {
          "limitId": "codex",
          "limitName": "Codex",
          "planType": "pro",
          "primary": {
            "usedPercent": 33,
            "windowDurationMins": 10080,
            "resetsAt": 1785645051
          },
          "secondary": null,
          "rateLimitReachedType": null
        },
        "rateLimitsByLimitId": {}
      }
      """
    )
    let primaryUsage = try WeeklyUsageSelector.select(
      from: primaryWeekly,
      accountPlanType: nil
    )
    try expect(primaryUsage.usedPercent == 33, "选择 primary 周窗口")
    try expect(primaryUsage.remainingPercent == 67, "计算剩余额度")
    try expect(primaryUsage.windowDurationMinutes == 10_080, "保留周窗口长度")
    try expect(primaryUsage.planType == "pro", "读取套餐")
    try expect(primaryUsage.limitName == "Codex", "读取限额名称")
    try expect(
      primaryUsage.resetsAt == Date(timeIntervalSince1970: 1_785_645_051),
      "解析重置时间"
    )

    let secondaryWeekly = try decodeRateLimits(
      """
      {
        "rateLimits": {
          "limitId": "codex",
          "primary": {
            "usedPercent": 5,
            "windowDurationMins": 300,
            "resetsAt": 1000
          },
          "secondary": {
            "usedPercent": 61.5,
            "windowDurationMins": 10080,
            "resetsAt": 2000
          }
        }
      }
      """
    )
    let secondaryUsage = try WeeklyUsageSelector.select(
      from: secondaryWeekly,
      accountPlanType: "plus"
    )
    try expect(secondaryUsage.usedPercent == 61.5, "从 secondary 选择周窗口")
    try expect(secondaryUsage.planType == "plus", "使用账号套餐兜底")

    let mappedWeekly = try decodeRateLimits(
      """
      {
        "rateLimits": null,
        "rateLimitsByLimitId": {
          "codex": {
            "limitId": "codex",
            "primary": {
              "usedPercent": 42,
              "windowDurationMins": 10080,
              "resetsAt": 3000
            }
          }
        }
      }
      """
    )
    let mappedUsage = try WeeklyUsageSelector.select(
      from: mappedWeekly,
      accountPlanType: "business"
    )
    try expect(mappedUsage.usedPercent == 42, "从 rateLimitsByLimitId 兜底")
    try expect(mappedUsage.limitName == "codex", "保留 limit ID")

    let clampedWeekly = try decodeRateLimits(
      """
      {
        "rateLimits": {
          "primary": {
            "usedPercent": 120,
            "windowDurationMins": 10080
          }
        }
      }
      """
    )
    let clampedUsage = try WeeklyUsageSelector.select(
      from: clampedWeekly,
      accountPlanType: nil
    )
    try expect(clampedUsage.usedPercent == 100, "限制异常百分比范围")

    let shortWindow = try decodeRateLimits(
      """
      {
        "rateLimits": {
          "primary": {
            "usedPercent": 10,
            "windowDurationMins": 300
          }
        }
      }
      """
    )
    do {
      _ = try WeeklyUsageSelector.select(from: shortWindow, accountPlanType: nil)
      throw VerificationFailure("拒绝把短周期误认为周限额")
    } catch UsageSelectionError.noWeeklyWindow {
      print("PASS 拒绝把短周期误认为周限额")
    }

    try verifyExecutableOverride()
    try verifySharedUsageStore()
  }

  private static func runIntegrationCheck() async throws {
    let snapshot = try await CodexAppServerClient().fetchUsage()
    try expect((0...100).contains(snapshot.usedPercent), "实时使用率范围")
    try expect(snapshot.windowDurationMinutes == 10_080, "实时周窗口长度")
    print(
      "PASS 实时 Codex 数据：已用 \(Int(snapshot.usedPercent.rounded()))%，"
        + "剩余 \(Int(snapshot.remainingPercent.rounded()))%"
    )
  }

  private static func verifyExecutableOverride() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let executable = temporaryDirectory.appendingPathComponent("codex")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )

    let resolved = try CodexExecutableLocator.resolve(
      environment: [
        "CODEX_BINARY_PATH": executable.path,
        "PATH": "",
      ],
      homeDirectory: temporaryDirectory.path
    )
    try expect(resolved.path == executable.path, "优先使用 CODEX_BINARY_PATH")
  }

  private static func verifySharedUsageStore() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let updatedAt = Date(timeIntervalSince1970: 1_785_645_051)
    let snapshot = SharedUsageSnapshot(
      usedPercent: 120,
      resetsAt: updatedAt.addingTimeInterval(3_600),
      planType: "pro",
      limitName: "Codex",
      updatedAt: updatedAt
    )
    try expect(snapshot.usedPercent == 100, "共享快照限制使用率范围")
    try expect(snapshot.remainingPercent == 0, "共享快照计算剩余额度")
    try expect(
      snapshot.isStale(
        relativeTo: updatedAt.addingTimeInterval(901)
      ),
      "共享快照识别过期数据"
    )

    let store = SharedUsageStore(directoryURL: temporaryDirectory)
    try store.save(snapshot)
    try expect(store.load() == snapshot, "共享快照原子写入与读取")
  }

  private static func decodeRateLimits(_ json: String) throws -> RateLimitsReadResult {
    try JSONDecoder().decode(
      RateLimitsReadResult.self,
      from: Data(json.utf8)
    )
  }

  private static func expect(
    _ condition: @autoclosure () -> Bool,
    _ name: String
  ) throws {
    guard condition() else {
      throw VerificationFailure(name)
    }
    print("PASS \(name)")
  }
}

private struct VerificationFailure: LocalizedError {
  let name: String

  init(_ name: String) {
    self.name = name
  }

  var errorDescription: String? {
    "检查未通过：\(name)"
  }
}
