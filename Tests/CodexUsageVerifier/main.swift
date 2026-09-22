import CodexUsageCore
import CodexUsageShared
import Darwin
import Foundation

@main
struct CodexUsageVerifier {
  static func main() async {
    do {
      try runUnitChecks()
      try verifyModernKimiUsage()
      try await verifyAppServerCompatibility()
      try await verifyLocalSnapshotBridge()
      if CommandLine.arguments.contains("--integration") {
        try await runIntegrationCheck()
      }
      if CommandLine.arguments.contains("--kimi-integration") {
        try await runKimiIntegrationCheck()
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
    try expect(
      secondaryUsage.fiveHourWindow?.usedPercent == 5,
      "提取五小时限额窗口"
    )
    try expect(
      secondaryUsage.fiveHourWindow?.resetsAt
        == Date(timeIntervalSince1970: 1_000),
      "五小时限额重置时间"
    )
    try expect(primaryUsage.fiveHourWindow == nil, "无五小时窗口时不展示")

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
    try verifyKimiUsageMapping()
    try verifyAppLanguage()
  }

  private static func verifyKimiUsageMapping() throws {
    let payload = """
      {
        "user": {
          "userId": "u1",
          "membership": { "level": "LEVEL_INTERMEDIATE" }
        },
        "usage": {
          "limit": "100",
          "used": "17",
          "remaining": "83",
          "resetTime": "2026-07-31T03:22:24.930601Z"
        },
        "limits": [
          {
            "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
            "detail": {
              "limit": "100",
              "used": "20",
              "remaining": "80",
              "resetTime": "2026-07-31T02:22:24.930601Z"
            }
          }
        ]
      }
      """
    let snapshot = try KimiUsageMapper.snapshot(from: Data(payload.utf8))
    try expect(snapshot.usedPercent == 17, "Kimi 解析已用百分比")
    try expect(snapshot.remainingPercent == 83, "Kimi 计算剩余额度")
    try expect(snapshot.planType == "intermediate", "Kimi 映射套餐等级")
    try expect(snapshot.limitName == "Kimi", "Kimi 设置限额名称")
    try expect(snapshot.windowDurationMinutes == 0, "Kimi 主窗口时长未知")

    let resetFormatter = ISO8601DateFormatter()
    resetFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    try expect(
      snapshot.resetsAt
        == resetFormatter.date(
          from: "2026-07-31T03:22:24.930601Z"
        ),
      "Kimi 解析重置时间"
    )

    try expect(
      snapshot.fiveHourWindow?.usedPercent == 20,
      "Kimi 提取五小时限额"
    )
    try expect(
      snapshot.fiveHourWindow?.windowDurationMinutes == 300,
      "Kimi 五小时窗口长度"
    )
    try expect(
      snapshot.fiveHourWindow?.resetsAt
        == resetFormatter.date(from: "2026-07-31T02:22:24.930601Z"),
      "Kimi 五小时限额重置时间"
    )

    let remainingOnlyPayload = """
      {
        "user": { "membership": { "level": "LEVEL_INTERMEDIATE" } },
        "usage": {
          "limit": 100,
          "remaining": 83,
          "reset_time": "2026-07-31T03:22:24.930601Z"
        },
        "limits": [
          {
            "window": {
              "duration": 300,
              "time_unit": "TIME_UNIT_MINUTE"
            },
            "detail": {
              "limit": 100,
              "remaining": 80,
              "reset_time": "2026-07-31T02:22:24.930601Z"
            }
          }
        ]
      }
      """
    let remainingOnly = try KimiUsageMapper.snapshot(
      from: Data(remainingOnlyPayload.utf8)
    )
    try expect(
      remainingOnly.usedPercent == 17
        && remainingOnly.fiveHourWindow?.usedPercent == 20,
      "Kimi 兼容 remaining-only 和 snake_case 响应"
    )

    let withoutLimits = try KimiUsageMapper.snapshot(
      from: Data(
        "{\"usage\":{\"limit\":\"100\",\"used\":\"17\"}}".utf8
      )
    )
    try expect(
      withoutLimits.fiveHourWindow == nil,
      "Kimi 无 limits 字段时隐藏五小时限额"
    )

    let emptyLimits = try KimiUsageMapper.snapshot(
      from: Data(
        "{\"usage\":{\"limit\":\"100\",\"used\":\"17\"},\"limits\":[]}".utf8
      )
    )
    try expect(
      emptyLimits.fiveHourWindow == nil,
      "Kimi 空 limits 数组时隐藏五小时限额"
    )

    do {
      _ = try KimiUsageMapper.snapshot(
        from: Data("{\"usage\":{\"limit\":\"0\",\"used\":\"1\"}}".utf8)
      )
      throw VerificationFailure("Kimi 拒绝无效额度数据")
    } catch KimiUsageClientError.invalidResponse {
      print("PASS Kimi 拒绝无效额度数据")
    }

    let credentials = try JSONDecoder().decode(
      KimiCredentials.self,
      from: Data(
        "{\"access_token\":\"a\",\"refresh_token\":\"b\",\"expires_at\":4102444800}"
          .utf8
      )
    )
    try expect(
      credentials.isAccessTokenValid(
        at: Date(timeIntervalSince1970: 1_700_000_000)
      ),
      "Kimi 凭证在有效期内"
    )
    try expect(
      !credentials.isAccessTokenValid(
        at: Date(timeIntervalSince1970: 4_103_000_000)
      ),
      "Kimi 凭证过期识别"
    )
    try expect(
      UsageSubscription.resolve("k3") == .kimi
        && UsageSubscription.resolve(nil) == .codex
        && UsageSubscription.resolve("unknown") == .codex,
      "订阅选择解析与兜底"
    )
  }

  private static func verifyModernKimiUsage() throws {
    func mapped(_ object: [String: Any]) throws -> UsageSnapshot {
      try KimiUsageMapper.snapshot(from: JSONSerialization.data(withJSONObject: object))
    }
    let windows: [String: Any] = [
      "limit_month_total": ["used_ratio": 0.25, "reset_time": "2026-10-01T00:00:00Z"],
      "limit_month_code": ["used_ratio": 0.1],
      "limit_7d": ["used_ratio": "0.4", "reset_time": "2026-09-25T00:00:00Z"],
      "limit_5h": ["used_ratio": 0.8, "reset_time": "2026-09-22T12:00:00Z"],
    ]
    let modern = try mapped(["usages": windows])
    let camelCase = try mapped([
      "usages": [
        "limitMonthTotal": ["usedRatio": "0.25"],
        "limit7d": ["usedRatio": 0.4],
        "limit5h": ["usedRatio": 0.8],
      ]
    ])
    try expect(
      camelCase.quotaWindows?.map(\.usedPercent) == [25, 40, 80],
      "Kimi 新版窗口同时兼容 camelCase 字段"
    )
    try expect(modern.usedPercent == 25, "Kimi 月总额度优先，Code 构成不重复累加")
    try expect(
      modern.quotaWindows?.map(\.kind) == [.monthly, .weekly, .fiveHour]
        && modern.quotaWindows?.map(\.usedPercent) == [25, 40, 80],
      "Kimi 解析新版数字及字符串比例，保留三个独立窗口"
    )
    try expect(
      modern.quotaWindows?.compactMap(\.resetsAt).count == 3
        && Set(modern.quotaWindows?.compactMap(\.resetsAt) ?? []).count == 3
        && modern.resetsAt == ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"),
      "Kimi 各窗口保留独立重置时间，主重置跟随月额度"
    )
    let newPlan = try mapped([
      "usages": [
        "limit_month_total": ["used_ratio": 0],
        "limit_5h": ["used_ratio": 0.5],
      ]
    ])
    try expect(
      newPlan.quotaWindows?.map(\.kind) == [.monthly, .fiveHour] && newPlan.usedPercent == 0,
      "Kimi 新套餐不虚构周窗口，真实零用量仍可显示"
    )
    let weeklyOnly = try mapped(["usages": ["limit_7d": ["used_ratio": "0.5"]]])
    let shortOnly = try mapped(["usages": ["limit_5h": ["used_ratio": 0.5]]])
    try expect(
      weeklyOnly.quotaWindows?.first?.kind == .weekly
        && shortOnly.quotaWindows?.first?.kind == .fiveHour
        && shortOnly.windowDurationMinutes == 300,
      "Kimi 缺月额度时回退明确的周或五小时口径"
    )
    let mixed = try mapped(["usages": windows, "usage": ["limit": 100, "used": 99]])
    try expect(mixed.usedPercent == 25, "Kimi 新旧响应并存时优先采用新版窗口")
    let legacyFallback = try mapped(["usages": [:], "usage": ["limit": 100, "remaining": 60]])
    try expect(
      legacyFallback.usedPercent == 40 && legacyFallback.quotaWindows == nil,
      "Kimi 无新版窗口时保留旧解析，不将未知口径推断为月额度"
    )
    let partial = try mapped([
      "usages": [
        "limit_month_total": "invalid",
        "limit_7d": ["used_ratio": -1],
        "limit_5h": ["used_ratio": 0.5, "reset_time": "invalid"],
      ]
    ])
    try expect(
      partial.quotaWindows?.map(\.kind) == [.fiveHour] && partial.resetsAt == nil,
      "Kimi 隔离无效窗口，未知重置时间不影响有效用量"
    )
    let saturated = try mapped(["usages": ["limit_month_total": ["used_ratio": 1.2]]])
    try expect(saturated.usedPercent == 100, "Kimi 超限比例显示上限 100%")
    let invalidPayloads: [[String: Any]] = [
      ["usages": [:]],
      ["usages": ["limit_month_code": ["used_ratio": 0.3]]],
      ["usages": ["limit_month_total": ["used_ratio": "NaN"]]],
      ["usages": ["limit_month_total": ["used_ratio": "Infinity"]]],
      ["usages": ["limit_month_total": ["used_ratio": -0.1]]],
      ["usages": ["limit_month_total": ["reset_time": "2026-10-01T00:00:00Z"]]],
      ["usage": ["limit": "Infinity", "used": 2]],
      ["usage": ["limit": 100, "used": "NaN"]],
    ]
    for object in invalidPayloads {
      do {
        _ = try mapped(object)
        throw VerificationFailure("Kimi 无效或缺失用量不能显示为 0%")
      } catch KimiUsageClientError.invalidResponse {}
    }
    print("PASS Kimi 无效或缺失用量不能显示为 0%")

    let oldSubscription = try JSONDecoder().decode(
      UsageSubscription.self, from: Data("\"k3\"".utf8))
    let encodedSubscription = try JSONEncoder().encode(oldSubscription)
    try expect(
      oldSubscription == .kimi && UsageSubscription.resolve("kimi") == .kimi
        && String(data: encodedSubscription, encoding: .utf8) == "\"kimi\"",
      "Kimi 兼容旧订阅解码，统一写入新标识"
    )
    let legacy = try JSONDecoder().decode(
      SharedUsageSnapshot.self,
      from: Data(
        """
        {"usedPercent":35,"updatedAt":1000,"limitName":"K3","subscriptionID":"k3",
         "fiveHourUsedPercent":60,"fiveHourResetsAt":2000}
        """.utf8
      ))
    let restored = UsageSnapshot(shared: legacy)
    let migrated = restored.shared(
      subscription: .kimi, language: .english, updatedAt: legacy.updatedAt)
    try expect(
      restored.limitName == "Kimi" && migrated.subscriptionID == "kimi"
        && migrated.displayQuotas.map(\.kind) == [.unknown, .fiveHour]
        && migrated.usedPercent == 35 && migrated.fiveHourUsedPercent == 60,
      "Kimi 旧快照升级保留用量，规范名称但不猜测额度周期"
    )
    let shared = modern.shared(subscription: .kimi, language: .english, updatedAt: Date())
    let roundTrip = try JSONDecoder().decode(
      SharedUsageSnapshot.self, from: JSONEncoder().encode(shared))
    try expect(
      roundTrip == shared && UsageSnapshot(shared: roundTrip).quotaWindows == modern.quotaWindows,
      "Kimi 主应用与 Widget 序列化往返保留全部窗口与重置时间"
    )
    try expect(
      roundTrip.primaryQuota.kind.title(in: .simplifiedChinese, for: .kimi) == "会员月额度"
        && shortOnly.shared(subscription: .kimi, language: .english, updatedAt: Date())
          .primaryQuota.kind.title(in: .english, for: .kimi) == "Code · 5-hour limit",
      "Kimi 回退窗口的显示及无障碍标签具有明确口径"
    )
    try expect(
      AppLanguage.english.localizedErrorMessage("Kimi 额度数据无法解析")
        == "Kimi usage data could not be parsed"
        && AppLanguage.english.localizedErrorMessage("Kimi 额度接口请求失败，状态码：401")
          == "Kimi usage request failed with status: 401",
      "Kimi 中英文错误文案同步更名"
    )
    let codex = SharedUsageSnapshot(
      usedPercent: 30, resetsAt: nil, planType: "pro", limitName: "Codex", updatedAt: Date(),
      fiveHourUsedPercent: 20
    )
    try expect(
      codex.displayQuotas.map(\.kind) == [.weekly, .fiveHour],
      "Codex 旧快照仍按周额度与五小时限额展示"
    )
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

  private static func verifyAppServerCompatibility() async throws {
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
    let script = """
      #!/bin/sh
      if [ "$2" = "--stdio" ]; then
        exit 64
      fi
      while IFS= read -r line; do
        case "$line" in
          *initialize*)
            printf '%s\\n' '{"id":0,"result":{}}'
            ;;
          *account/read*)
            printf '%s\\n' '{"id":1,"result":{"account":{"type":"chatgpt","planType":"pro"},"requiresOpenaiAuth":true}}'
            ;;
          *account/rateLimits/read*)
            printf '%s\\n' '{"id":2,"result":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":"12.5","window_duration_seconds":604800,"resets_at":1788138263}}}}'
            ;;
        esac
      done
      """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )

    let snapshot = try await CodexAppServerClient(
      executableURL: executable,
      timeout: 2
    ).fetchUsage()
    try expect(
      snapshot.usedPercent == 12.5
        && snapshot.windowDurationMinutes == 10_080
        && snapshot.planType == "pro",
      "兼容 CLI 参数回退、顺序握手、snake_case 和秒级窗口字段"
    )
  }

  private static func runKimiIntegrationCheck() async throws {
    let snapshot = try await KimiUsageClient().fetchUsage()
    try expect((0...100).contains(snapshot.usedPercent), "Kimi 实时使用率范围")
    try expect(snapshot.limitName == "Kimi", "Kimi 实时限额名称")
    print(
      "PASS 实时 Kimi 数据：已用 \(Int(snapshot.usedPercent.rounded()))%，"
        + "剩余 \(Int(snapshot.remainingPercent.rounded()))%，"
        + "套餐 \(snapshot.planType ?? "未知")"
    )
    if let fiveHour = snapshot.fiveHourWindow {
      print(
        "PASS 实时 Kimi 五小时限额：已用 "
          + "\(Int(fiveHour.usedPercent.rounded()))%"
      )
    } else {
      print("PASS 实时 Kimi 无五小时限额（按需隐藏）")
    }
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

    let kimiPreferences = SharedWidgetPreferences(
      languageCode: AppLanguage.simplifiedChinese.rawValue,
      subscriptionID: UsageSubscription.kimi.rawValue
    )
    try preferencesStore.save(kimiPreferences)
    try expect(
      preferencesStore.load() == kimiPreferences,
      "持久化 Widget 订阅选择"
    )

    let legacyPreferences = try JSONDecoder().decode(
      SharedWidgetPreferences.self,
      from: Data("{\"languageCode\":\"en\"}".utf8)
    )
    try expect(
      legacyPreferences.subscriptionID == nil,
      "兼容不含订阅字段的旧偏好"
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
    try expect(
      legacySnapshot.fiveHourUsedPercent == nil,
      "兼容不含五小时字段的旧 Widget 快照"
    )
    try expect(
      legacySnapshot.windowDurationMinutes == nil,
      "兼容不含窗口时长字段的旧 Widget 快照"
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
    try expect(
      AppLanguage.simplifiedChinese.text(.switchingLanguage) == "正在切换"
        && AppLanguage.english.text(.switchingLanguage) == "Switching",
      "提供中英文切换状态文案"
    )
    try verifyLanguageTransition()
  }

  private static func verifyLanguageTransition() throws {
    var transition = LanguageTransitionState(current: .simplifiedChinese)

    try expect(
      transition.request(.english, whileRefreshing: true) == .queued,
      "刷新期间暂存语言切换"
    )
    try expect(
      transition.current == .simplifiedChinese
        && transition.pending == .english
        && transition.isWaitingForRefresh,
      "暂存期间保持当前界面语言"
    )
    try expect(
      transition.finishRefreshing() == .applied(.english)
        && transition.current == .english
        && !transition.isWaitingForRefresh,
      "刷新完成后应用待切换语言"
    )
    try expect(
      transition.request(.simplifiedChinese, whileRefreshing: false)
        == .applied(.simplifiedChinese),
      "空闲状态立即应用语言切换"
    )
    try expect(
      transition.request(.english, whileRefreshing: true) == .queued
        && transition.request(.simplifiedChinese, whileRefreshing: true)
          == .ignored
        && transition.pending == .english
        && transition.isWaitingForRefresh,
      "切换期间忽略快速重复点击"
    )
    try expect(
      transition.finishRefreshing() == .applied(.english)
        && transition.current == .english
        && transition.pending == nil
        && !transition.isWaitingForRefresh,
      "快速点击后仍应用已确认语言"
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
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(
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
