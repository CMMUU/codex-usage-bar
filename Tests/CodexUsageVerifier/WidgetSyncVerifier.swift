import CodexUsageCore
import CodexUsageShared
import Darwin
import Foundation

enum WidgetSyncVerifier {
  static func run() async throws {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let oldSnapshot = SharedUsageSnapshot(
      usedPercent: 10, resetsAt: nil, planType: nil, limitName: "Codex",
      updatedAt: now.addingTimeInterval(-3_600),
      languageCode: "en", subscriptionID: "codex"
    )
    let snapshot = SharedUsageSnapshot(
      usedPercent: 45, resetsAt: nil, planType: nil, limitName: "Codex",
      updatedAt: now, languageCode: "zh-Hans", subscriptionID: "codex"
    )
    let old = SharedWidgetState(snapshot: oldSnapshot, languageCode: "en")
    let current = SharedWidgetState(
      snapshot: snapshot, languageCode: "zh-Hans", publishedAt: now
    )
    var fallbackReads = 0
    let liveSelection = WidgetSnapshotResolver.select(
      live: current,
      shared: {
        fallbackReads += 1
        return old
      },
      cached: {
        fallbackReads += 1
        return old
      })
    try check(
      liveSelection.state == current && liveSelection.source == .live && fallbackReads == 0,
      "实时数据可用时不触碰共享目录或旧缓存")
    let emptyLive = SharedWidgetState(
      snapshot: nil, languageCode: "en", subscriptionID: "kimi", publishedAt: now)
    let emptySelection = WidgetSnapshotResolver.select(
      live: emptyLive,
      shared: {
        fallbackReads += 1
        return old
      }, cached: { old })
    try check(
      emptySelection.state == emptyLive && fallbackReads == 0,
      "实时空状态也立即返回，不触发受限共享读取")
    let cacheSelection = WidgetSnapshotResolver.select(
      live: nil, shared: { nil }, cached: { current })
    try check(
      cacheSelection.source == .cached && cacheSelection.state == current,
      "回环和共享存储不可用时明确标记私有缓存来源")
    let disabledStore = SharedWidgetStateStore(appGroupIdentifier: "invalid.test", enabled: false)
    try check(disabledStore.load() == nil, "开发构建禁用未授权 App Group")
    let dates = WidgetTimelineSchedule.entryDates(updatedAt: now, now: now)
    try check(
      dates.count == 2 && snapshot.isStale(relativeTo: dates[1]),
      "预生成过期时间线，系统延迟刷新时也不会长期显示新鲜状态")
    try check(
      WidgetTimelineSchedule.entryDates(updatedAt: oldSnapshot.updatedAt, now: now) == [now],
      "旧额度直接显示过期，不为旧缓存延后刷新状态")
    try check(
      WidgetSnapshotResolver.resolve(live: current, shared: old, cached: old) == current,
      "实时额度优先于可读取的旧 App Group 和 Widget 缓存"
    )
    try check(
      WidgetSnapshotResolver.resolve(live: nil, shared: old, cached: current) == current,
      "主应用关闭后保留较新的 Widget 缓存"
    )
    try check(
      WidgetSnapshotResolver.resolve(live: nil, shared: current, cached: old) == current,
      "共享状态比 Widget 缓存更新时使用共享状态"
    )
    try check(
      WidgetSnapshotResolver.resolve(live: nil, shared: nil, cached: nil) == nil,
      "首次启动无数据时不虚构额度"
    )

    let switched = SharedWidgetState(
      snapshot: nil, languageCode: "zh-Hans", subscriptionID: "kimi",
      publishedAt: now.addingTimeInterval(1)
    )
    try check(
      WidgetSnapshotResolver.resolve(live: switched, shared: current, cached: old) == switched,
      "切换订阅尚未获取额度时立即清除上一订阅的数据"
    )
    try check(
      WidgetSnapshotResolver.resolve(live: nil, shared: current, cached: switched) == switched,
      "切换后的空状态持久化，离线时不恢复上一订阅的额度"
    )
    let mismatched = SharedWidgetState(
      snapshot: snapshot, languageCode: "en", subscriptionID: "kimi", publishedAt: now
    )
    try check(mismatched.snapshot == nil, "拒绝将 Codex 额度放入 Kimi 状态")
    let languageChange = SharedWidgetState(
      snapshot: snapshot, languageCode: "en", publishedAt: now.addingTimeInterval(2)
    )
    try check(
      WidgetSnapshotResolver.resolve(live: nil, shared: current, cached: languageChange)
        == languageChange && languageChange.snapshot?.updatedAt == now,
      "语言设置按发布时间同步，同时保留真实额度刷新时间"
    )
    try check(
      WidgetSnapshotResolver.resolve(live: current, shared: languageChange, cached: switched)
        == current,
      "运行中应用的状态不受其他缓存时间影响"
    )
    let legacyBytes = try JSONEncoder().encode(snapshot)
    try check(
      SharedWidgetState.decodeBridgeData(legacyBytes)?.snapshot == snapshot,
      "兼容旧版主应用发送的原始快照"
    )
    try check(
      SharedWidgetState.decodeBridgeData(Data("{\"languageCode\":\"en\"}".utf8))?
        .languageCode == "en",
      "兼容旧版仅含语言设置的回环状态"
    )
    try check(
      SharedWidgetState.decodeBridgeData(Data("{}".utf8)) == nil
        && SharedWidgetState.decodeBridgeData(Data(legacyBytes.prefix(20))) == nil,
      "拒绝空对象与不完整的回环 JSON"
    )
    var invalidObject =
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(current)) as! [String: Any]
    invalidObject["subscriptionID"] = "kimi"
    let decodedMismatch = SharedWidgetState.decodeBridgeData(
      try JSONSerialization.data(withJSONObject: invalidObject))
    try check(
      decodedMismatch?.snapshot == nil && decodedMismatch?.subscriptionID == "kimi",
      "反序列化状态也隔离订阅不匹配的数据"
    )

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SharedWidgetStateStore(directoryURL: directory)
    try store.save(current)
    try check(store.load() == current, "额度、语言、订阅作为一个状态原子持久化")
    try store.save(switched)
    try check(store.load() == switched, "空额度状态可完整保存与恢复")
    let legacyStore = SharedUsageStore(directoryURL: directory)
    try legacyStore.save(snapshot)
    try legacyStore.clear()
    try legacyStore.clear()
    try check(legacyStore.load() == nil, "清理旧版额度文件可重复执行")

    let fragmented = try FragmentedSnapshotServer(data: JSONEncoder().encode(current))
    defer { fragmented.stop() }
    let received = await load(ports: [fragmented.port])
    try check(received == current, "TCP 多段到达时完整读取状态，不回退到旧缓存")

    let oversized = try FragmentedSnapshotServer(
      data: Data(repeating: 32, count: LocalUsageSnapshotBridgeConfiguration.maximumPayloadSize + 1)
    )
    defer { oversized.stop() }
    let fallback = try FragmentedSnapshotServer(data: JSONEncoder().encode(switched))
    defer { fallback.stop() }
    let recovered = await load(ports: [oversized.port, fallback.port])
    try check(recovered == switched, "超大回环响应被拒绝后继续尝试下一个端口")

    let truncated = try FragmentedSnapshotServer(data: Data(legacyBytes.prefix(20)))
    defer { truncated.stop() }
    let partial = await load(ports: [truncated.port])
    try check(partial == nil, "连接关闭但 JSON 不完整时不发布错误状态")

    let bailian = try verifyProviderContracts(at: now)
    try verifyStatusLineCapture(at: now, directory: directory)
    try await verifyCopilotProcess(directory: directory)
    try await verifyDetailsSync(
      bailian, replacing: current, at: now, store: store)
  }

  private static func verifyProviderContracts(at now: Date) throws -> SubscriptionUsageDetails {
    try check(
      Set(SubscriptionUsageAdapter.defaults().keys) == Set(UsageSubscription.allCases)
        && UsageSubscription.allCases.count == 9,
      "九类订阅各有一个读取适配器")

    let claude = try ClaudeUsageClient.decodeStatusLine(
      Data(
        """
        {"rate_limits":{"seven_day":{"used_percentage":37.5,"resets_at":1790003600},
         "five_hour":{"used_percentage":0},"spend_limit":{"used_percentage":80}},
         "context_window":{"used_percentage":23}}
        """.utf8), observedAt: now)
    try check(
      claude?.subscriptionID == "claude" && claude?.planName == nil
        && claude?.quotas.map(\.usedAmount) == [37.5, 0]
        && claude?.primaryQuota?.resetsAt == now.addingTimeInterval(3600),
      "Claude Code 只读取官方订阅周期并保留真实零用量")
    let gateway = try ClaudeUsageClient.decodeStatusLine(
      Data(#"{"rate_limits":{"spend_limit":{"used_percentage":25}}}"#.utf8), observedAt: now)
    try check(gateway == nil, "Claude Code 网关支出不会混入订阅额度")

    let antigravity = try AntigravityUsageClient.decodeStatusLine(
      Data(
        """
        {"product":"antigravity","plan_tier":"Pro","quota":{
          "gemini-weekly":{"remaining_fraction":0.75,"reset_in_seconds":3600},
          "other":{"remaining_amount":320},"disabled":{"remaining_fraction":1,"disabled":true}
        }}
        """.utf8), observedAt: now)
    try check(
      antigravity?.planName == "Pro" && antigravity?.quotas.count == 2
        && antigravity?.primaryQuota?.usedAmount == 25
        && antigravity?.primaryQuota?.resetsAt == now.addingTimeInterval(3600),
      "Antigravity 保留档位、周期、剩余比例和重置时间")
    try check(
      antigravity?.quotas.last?.remainingAmount == 320
        && antigravity?.quotas.last?.usedAmount == nil
        && antigravity?.quotas.last?.usedPercent == nil,
      "Antigravity 仅返回余额时保持已用和比例未知")

    let glm = try GLMUsageClient.decodeUsage(
      Data(
        """
        {"data":{"level":"max","limits":[
          {"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":12},
          {"type":"TOKENS_LIMIT","unit":6,"number":1,"percentage":42,"nextResetTime":1790003600000},
          {"type":"TIME_LIMIT","unit":5,"number":1,"currentValue":4,"usage":100},
          {"type":"TOKENS_LIMIT","unit":5,"number":1,"percentage":true}
        ]}}
        """.utf8), observedAt: now)
    try check(
      glm.planName == "max" && glm.quotas.map(\.kind) == [.weekly, .fiveHour, .monthly]
        && glm.quotas.map(\.usedAmount) == [42, 12, 4] && glm.quotas.last?.remainingAmount == 96
        && glm.primaryQuota?.resetsAt == now.addingTimeInterval(3600),
      "智谱 GLM 旧口径区分周、五小时和 MCP 月额度，拒绝布尔数值")
    let glmCredits = try GLMUsageClient.decodeUsage(
      Data(
        """
        {"data":{"level":"lite","limits":[
          {"type":"CREDIT_LIMIT","unit":3,"number":5,"usage":2000,"currentValue":2005,"remaining":0},
          {"type":"CREDIT_LIMIT","unit":6,"number":1,"usage":10000,"currentValue":2005,"remaining":7994}
        ]}}
        """.utf8), observedAt: now)
    try check(
      glmCredits.primaryQuota?.unit == .credits && glmCredits.primaryQuota?.remainingAmount == 7994
        && glmCredits.quotas.last?.usedAmount == 2005 && glmCredits.quotas.last?.usedPercent == 100,
      "智谱 GLM 积分保留服务端绝对数和超限读数")

    let miniMax = try MiniMaxUsageClient.decodeUsage(
      Data(
        """
        {"base_resp":{"status_code":0},"model_remains":[
          {"model_name":"general","current_interval_total_count":0,"current_interval_usage_count":0,
           "current_interval_remaining_percent":42,"remains_time":3600000,
           "current_weekly_status":3},
          {"model_name":"counted","start_time":1790000000000,"end_time":1790018000000,
           "current_interval_total_count":100,"current_interval_usage_count":25,
           "current_weekly_total_count":100,"current_weekly_usage_count":25,
           "current_weekly_remaining_percent":75,"weekly_end_time":1790604800000},
          {"model_name":"outside-plan","current_interval_total_count":0,"current_interval_status":3,
           "current_weekly_total_count":0,"current_weekly_status":3}
        ]}
        """.utf8), observedAt: now)
    try check(
      miniMax.quotas.count == 4 && miniMax.primaryQuota?.remainingAmount == 42
        && miniMax.primaryQuota?.resetsAt == now.addingTimeInterval(3600)
        && miniMax.quotas[1].isUnlimited,
      "MiniMax 时间额度优先读取有效百分比，并区分未包含与不限量")
    try check(
      miniMax.quotas[2].remainingAmount == 25 && miniMax.quotas[2].kind == .fiveHour
        && miniMax.quotas[3].remainingAmount == 75
        && miniMax.quotas[3].resetsAt == now.addingTimeInterval(604_800),
      "MiniMax 兼容两种次数含义，保留独立的周重置")

    let bailian = try BailianUsageClient.decodeUsage(
      Data(
        """
        {"instanceType":"pro","per5Hour":{"usedQuota":0,"totalQuota":150,"resetTime":1790000120000},
         "perWeek":{},"perBillMonth":{"usedQuota":420,"totalQuota":1000,"resetTime":1791000000000}}
        """.utf8), observedAt: now)
    try check(
      bailian.planName == "pro" && bailian.quotas.map(\.kind) == [.monthly, .fiveHour]
        && bailian.primaryQuota?.usedAmount == 420 && bailian.primaryQuota?.remainingAmount == 580
        && bailian.quotas.last?.usedAmount == 0
        && bailian.quotas.last?.resetsAt == now.addingTimeInterval(120),
      "百炼保留套餐和次数，跳过官方 CLI 的空窗口")

    let ark = try VolcengineArkUsageClient.decodeUsage(
      Data(
        """
        {"viewer":{"user_name":"fixture-viewer"},"items":[
          {"product":"coding-plan-team","edition":"team","tier":"large","subscribed":true,
           "periods":[{"label":"weekly","percent":80}]},
          {"product":"coding-plan","edition":"personal","subscribed":true,"updated_at":1789999990000,
           "periods":[{"label":"session","percent":22,"reset_at":"2026-09-21T22:00:00+08:00"},
                      {"label":"weekly","percent":64}]}
        ]}
        """.utf8), observedAt: now)
    try check(
      ark.planName == nil && ark.quotas.map(\.usedAmount) == [64, 22]
        && ark.primaryQuota?.unit == .percent && ark.primaryQuota?.limit == nil
        && ark.observedAt == now.addingTimeInterval(-10)
        && ark.quotas.last?.resetsAt == Date(timeIntervalSince1970: 1_789_999_200),
      "火山方舟只采用个人 Coding Plan，保留原始更新时间与百分比")
    return bailian
  }

  private static func verifyStatusLineCapture(at now: Date, directory: URL) throws {
    let data = Data(
      """
      {"product":"antigravity","plan_tier":"Pro","email":"fixture@example.test",
       "quota":{"gemini-weekly":{"remaining_fraction":0.75,"reset_time":"2026-12-01T15:30:00Z"}}}
      """.utf8)
    let initial = try SubscriptionStatusLineCapture.ingest(
      data, for: .antigravity, observedAt: now, directory: directory)
    let duplicate = try SubscriptionStatusLineCapture.ingest(
      data, for: .antigravity, observedAt: now.addingTimeInterval(60), directory: directory)
    let older = Data(
      """
      {"product":"antigravity","quota":{"gemini-weekly":{"remaining_fraction":0.90}}}
      """.utf8)
    let reordered = try SubscriptionStatusLineCapture.ingest(
      older, for: .antigravity, observedAt: now.addingTimeInterval(-1), directory: directory)
    let stored = try SubscriptionStatusLineCapture.load(for: .antigravity, directory: directory)
    try check(
      initial == stored && stored.observedAt == now && duplicate == nil && reordered == nil,
      "状态行重复与乱序更新保留最新有效读数及原采集时间")
    let captureFile = directory.appendingPathComponent("status-line/antigravity.json")
    let saved = try String(contentsOf: captureFile, encoding: .utf8)
    try check(
      !saved.contains("fixture@example.test") && !saved.contains("remaining_fraction"),
      "状态行本地文件仅写规范化额度，省略账号与原始载荷")
  }

  private static func verifyCopilotProcess(directory: URL) async throws {
    let executable = directory.appendingPathComponent("copilot-fixture")
    let script = #"""
      #!/usr/bin/python3
      import json
      import sys
      import time

      assert sys.argv[1:] == ["--headless", "--no-auto-update", "--stdio"]
      for method, result in [
          ("connect", {"protocolVersion": 3}),
          ("auth.getStatus", {"isAuthenticated": True}),
          ("account.getQuota", {"quotaSnapshots": {
              "premium_interactions": {"entitlementRequests": 400, "usedRequests": 70,
                  "remainingPercentage": 82.5, "resetDate": "2026-12-01T00:00:00Z"},
              "chat": {"isUnlimitedEntitlement": True, "entitlementRequests": -1, "usedRequests": 90}
          }})
      ]:
          header = sys.stdin.buffer.readline()
          size = int(header.split(b":")[1].strip())
          assert sys.stdin.buffer.readline() == b"\r\n"
          message = json.loads(sys.stdin.buffer.read(size))
          assert message["method"] == method
          body = json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": result}).encode()
          frame = b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body
          sys.stdout.buffer.write(frame[:12])
          sys.stdout.flush()
          time.sleep(0.02)
          sys.stdout.buffer.write(frame[12:])
          sys.stdout.flush()
      """#
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let result = try await CopilotUsageClient(executable: executable).fetchUsage()
    try check(
      result.primaryQuota?.usedAmount == 70 && result.primaryQuota?.remainingAmount == 330
        && result.primaryQuota?.resetsAt != nil && result.quotas.last?.isUnlimited == true
        && result.quotas.last?.usedAmount == 90,
      "Copilot 子进程握手、登录状态和分段额度 RPC 通过，保留不限量")
  }

  private static func verifyDetailsSync(
    _ details: SubscriptionUsageDetails, replacing previous: SharedWidgetState,
    at now: Date, store: SharedWidgetStateStore
  ) async throws {
    let state = SharedWidgetState(
      snapshot: previous.snapshot, languageCode: "zh-Hans", subscriptionID: "bailian",
      publishedAt: now.addingTimeInterval(1), details: details)
    try store.save(state)
    let peer = try FragmentedSnapshotServer(data: JSONEncoder().encode(state))
    defer { peer.stop() }
    let received = await load(ports: [peer.port])
    try check(
      state.snapshot == nil && store.load() == state && received == state
        && received?.displayDetails == details,
      "新订阅在磁盘与分段回环完整同步套餐、额度、单位、重置时间和语言")

    let switched = SharedWidgetState(
      snapshot: nil, languageCode: "en", subscriptionID: "glm",
      publishedAt: now.addingTimeInterval(2),
      details: SubscriptionUsageDetails(subscription: .glm, availability: .notConnected))
    let fallback = WidgetSnapshotResolver.resolve(live: nil, shared: switched, cached: state)
    try check(
      fallback?.subscriptionID == "glm" && fallback?.displayDetails?.availability == .notConnected
        && fallback?.displayDetails?.quotas.isEmpty == true,
      "切换未连接订阅后，离线回退也不会恢复上一订阅的额度")

    let mismatch = SharedWidgetState(
      snapshot: nil, languageCode: "en", subscriptionID: "glm", details: details)
    let future = SharedWidgetState(
      snapshot: previous.snapshot, languageCode: "en", subscriptionID: "unknown-service")
    try check(
      mismatch.displayDetails == nil && future.displayDetails == nil,
      "拒绝跨订阅详情与未知订阅标识冒用 Codex 额度")
    let legacyKimi = SharedUsageSnapshot(
      usedPercent: 22, resetsAt: nil, planType: "moderato", limitName: "K3",
      updatedAt: now, subscriptionID: "k3")
    let migrated = SharedWidgetState(
      snapshot: legacyKimi, languageCode: "en", subscriptionID: "kimi")
    try check(
      migrated.displayDetails?.subscriptionID == "kimi"
        && migrated.displayDetails?.primaryQuota?.usedAmount == 22,
      "共享详情兼容旧 k3 标识和百分比快照")
    try check(
      details.primaryQuota?.menuBarValue(in: .english) == "Used 420 requests"
        && details.primaryQuota?.usedText(in: .english) == "420 requests"
        && details.primaryQuota?.remainingText(in: .simplifiedChinese) == "580 次",
      "菜单栏与详情使用一致数值并按语言显示原始单位")
    try check(
      !details.isStale(relativeTo: now) && details.isStale(relativeTo: now.addingTimeInterval(121))
        && details.observedAt == now,
      "额度过期保留原始观测时间")
  }

  private static func load(ports: [UInt16]) async -> SharedWidgetState? {
    await withCheckedContinuation { continuation in
      LocalUsageSnapshotClient(ports: ports).loadPayload {
        continuation.resume(returning: $0)
      }
    }
  }

  private static func check(_ condition: Bool, _ name: String) throws {
    guard condition else { throw NSError(domain: name, code: 1) }
    print("PASS \(name)")
  }
}

/// A real loopback peer splits JSON across writes, independently of Network.framework.
private final class FragmentedSnapshotServer: @unchecked Sendable {
  let port: UInt16
  private let listener: Int32

  init(data: Data) throws {
    let listener = socket(AF_INET, SOCK_STREAM, 0)
    guard listener >= 0 else { throw POSIXError(.EIO) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    var size = socklen_t(MemoryLayout<sockaddr_in>.size)
    let inspected = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(listener, $0, &size)
      }
    }
    guard bound == 0, inspected == 0, listen(listener, 1) == 0 else {
      close(listener)
      throw POSIXError(.EIO)
    }
    port = UInt16(bigEndian: address.sin_port)
    self.listener = listener
    let descriptor = listener
    DispatchQueue.global().async {
      let connection = accept(descriptor, nil, nil)
      guard connection >= 0 else { return }
      defer { close(connection) }
      var enabled: Int32 = 1
      setsockopt(
        connection, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
      let pieces = [Data(data.prefix(13)), Data(data.dropFirst(13))]
      for piece in pieces {
        let success = piece.withUnsafeBytes { bytes -> Bool in
          var offset = 0
          while offset < bytes.count {
            let sent = send(
              connection, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
            guard sent > 0 else { return false }
            offset += sent
          }
          return true
        }
        guard success else { return }
        usleep(60_000)
      }
    }
  }

  func stop() {
    shutdown(listener, SHUT_RDWR)
    close(listener)
  }
}
