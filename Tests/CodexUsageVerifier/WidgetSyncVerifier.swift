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
