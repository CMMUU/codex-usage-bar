import CodexUsageCore
import CodexUsageShared
import Darwin
import Foundation

@main
struct CodexUsageVerifier {
  static func main() async {
    do {
      try runUnitChecks()
      try await verifyLocalSnapshotBridge()
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
    try verifyAppLanguage()
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
      updatedAt: updatedAt,
      languageCode: AppLanguage.english.rawValue
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
    try expect(
      store.load()?.languageCode == AppLanguage.english.rawValue,
      "共享快照保留 Widget 语言"
    )

    let preferencesStore = SharedWidgetPreferencesStore(
      directoryURL: temporaryDirectory
    )
    let preferences = SharedWidgetPreferences(
      languageCode: AppLanguage.english.rawValue
    )
    try preferencesStore.save(preferences)
    try expect(
      preferencesStore.load() == preferences,
      "独立持久化 Widget 语言设置"
    )

    let legacySnapshotData = try JSONSerialization.data(
      withJSONObject: [
        "usedPercent": 25,
        "updatedAt": updatedAt.timeIntervalSinceReferenceDate,
      ]
    )
    let legacySnapshot = try JSONDecoder().decode(
      SharedUsageSnapshot.self,
      from: legacySnapshotData
    )
    try expect(
      legacySnapshot.languageCode == nil,
      "兼容不含语言字段的旧 Widget 快照"
    )
  }

  private static func verifyAppLanguage() throws {
    let defaultsSuite = "CodexUsageVerifier.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
      throw VerificationFailure("创建语言偏好测试存储")
    }
    defer {
      defaults.removePersistentDomain(forName: defaultsSuite)
    }
    defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)

    try expect(
      AppLanguage.resolve("zh-Hans") == .simplifiedChinese,
      "恢复已保存的中文选择"
    )
    try expect(
      AppLanguage.resolve("en") == .english,
      "恢复已保存的英文选择"
    )
    try expect(
      AppLanguage.resolve(
        defaults.string(forKey: AppLanguage.storageKey)
      ) == .english,
      "持久化用户语言选择"
    )
    try expect(
      AppLanguage.simplifiedChinese.toggled == .english
        && AppLanguage.english.toggled == .simplifiedChinese,
      "中英文切换可逆"
    )
    try expect(
      AppLanguage.simplifiedChinese.text(.weeklyUsed) == "本周已用"
        && AppLanguage.english.text(.weeklyUsed) == "Used this week",
      "提供中英文界面文案"
    )
    try expect(
      AppLanguage.english.localizedErrorMessage("读取 Codex 限额超时")
        == "Timed out while reading the Codex limit",
      "切换英文错误提示"
    )
    try expect(
      AppLanguage.english.widgetWaitingTitle == "Waiting for usage data"
        && AppLanguage.simplifiedChinese.widgetWaitingTitle == "等待用量数据",
      "提供中英文 Widget 文案"
    )
    try expect(
      AppLanguage.simplifiedChinese.text(.checkForUpdates) == "检查更新"
        && AppLanguage.english.text(.checkForUpdates) == "Check for updates",
      "提供中英文更新按钮文案"
    )
    try expect(
      AppLanguage.simplifiedChinese.text(.updateAvailable) == "新版本"
        && AppLanguage.english.text(.updateAvailable) == "New version",
      "提供中英文新版本提示"
    )
  }

  private static func verifyLocalSnapshotBridge() async throws {
    let basePort = UInt16.random(in: 54_000...59_000)
    let ports = [basePort, basePort + 1, basePort + 2]
    let updatedAt = Date(timeIntervalSince1970: 1_785_645_051)
    let expected = SharedUsageSnapshot(
      usedPercent: 47,
      resetsAt: updatedAt.addingTimeInterval(3_600),
      planType: "pro",
      limitName: "Codex",
      updatedAt: updatedAt,
      languageCode: AppLanguage.english.rawValue
    )
    let server = LocalUsageSnapshotServer(ports: ports)
    server.update(expected)
    server.start()
    defer {
      server.stop()
    }

    try await Task.sleep(nanoseconds: 150_000_000)
    let client = LocalUsageSnapshotClient(ports: ports)
    let received = await withCheckedContinuation { continuation in
      client.load { snapshot in
        continuation.resume(returning: snapshot)
      }
    }
    try expect(received == expected, "本机回环同步 Widget 快照")

    let languagePorts = [basePort + 10, basePort + 11, basePort + 12]
    let languageServer = LocalUsageSnapshotServer(ports: languagePorts)
    languageServer.updateLanguage(AppLanguage.simplifiedChinese.rawValue)
    languageServer.start()
    defer {
      languageServer.stop()
    }

    try await Task.sleep(nanoseconds: 150_000_000)
    let languageClient = LocalUsageSnapshotClient(ports: languagePorts)
    let languagePayload = await withCheckedContinuation { continuation in
      languageClient.loadPayload { payload in
        continuation.resume(returning: payload)
      }
    }
    try expect(
      languagePayload?.snapshot == nil
        && languagePayload?.languageCode
          == AppLanguage.simplifiedChinese.rawValue,
      "无用量快照时同步 Widget 语言设置"
    )
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
