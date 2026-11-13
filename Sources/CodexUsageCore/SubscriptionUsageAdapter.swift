import CodexUsageShared
import CoreFoundation
import Darwin
import Foundation

public enum SubscriptionUsageError: Error, Equatable, Sendable {
  case missingCLI, notConnected, waitingForStatusLine, unavailable, invalidResponse, timedOut,
    keychain

  public var availability: SubscriptionUsageAvailability {
    switch self {
    case .notConnected, .missingCLI: return .notConnected
    case .waitingForStatusLine: return .waiting
    default: return .unavailable
    }
  }

  public func text(in language: AppLanguage) -> String {
    switch self {
    case .missingCLI: return language.text(.quotaCLIUnavailable)
    case .keychain: return language.text(.quotaKeychainError)
    default: return language.quotaAvailabilityText(availability)
    }
  }
}

public struct SubscriptionUsageReading: Sendable {
  public let details: SubscriptionUsageDetails
  public let legacySnapshot: UsageSnapshot?
}

/// Each provider owns its data contract; the application has one fetch and publish path.
public struct SubscriptionUsageAdapter: Sendable {
  public let subscription: UsageSubscription
  private let read: @Sendable () async throws -> SubscriptionUsageReading

  private init(
    subscription: UsageSubscription,
    read: @escaping @Sendable () async throws -> SubscriptionUsageReading
  ) {
    self.subscription = subscription
    self.read = read
  }

  public func fetchUsage() async throws -> SubscriptionUsageReading {
    let result = try await read()
    guard result.details.subscriptionID == subscription.rawValue else {
      throw SubscriptionUsageError.invalidResponse
    }
    return result
  }

  public static func defaults(
    codex: CodexAppServerClient = CodexAppServerClient(),
    kimi: KimiUsageClient = KimiUsageClient(),
    credentials: SubscriptionCredentialStore = SubscriptionCredentialStore()
  ) -> [UsageSubscription: Self] {
    let claude = ClaudeUsageClient()
    let antigravity = AntigravityUsageClient()
    let copilot = CopilotUsageClient()
    let glm = GLMUsageClient(credentials: credentials)
    let minimax = MiniMaxUsageClient(credentials: credentials)
    let bailian = BailianUsageClient()
    let ark = VolcengineArkUsageClient()
    let sources: [Self] = [
      legacy(.codex) { try await codex.fetchUsage() },
      legacy(.kimi) { try await kimi.fetchUsage() },
      provider(.claude) { try await claude.fetchUsage() },
      provider(.antigravity) { try await antigravity.fetchUsage() },
      provider(.copilot) { try await copilot.fetchUsage() },
      provider(.glm) { try await glm.fetchUsage() },
      provider(.minimax) { try await minimax.fetchUsage() },
      provider(.bailian) { try await bailian.fetchUsage() },
      provider(.volcengineArk) { try await ark.fetchUsage() },
    ]
    return Dictionary(uniqueKeysWithValues: sources.map { ($0.subscription, $0) })
  }

  private static func legacy(
    _ subscription: UsageSubscription, _ read: @escaping @Sendable () async throws -> UsageSnapshot
  ) -> Self {
    Self(subscription: subscription) {
      let snapshot = try await read()
      let details = SubscriptionUsageDetails(
        legacy: snapshot.shared(subscription: subscription, language: .english, updatedAt: Date()),
        subscription: subscription)
      return SubscriptionUsageReading(details: details, legacySnapshot: snapshot)
    }
  }

  private static func provider(
    _ subscription: UsageSubscription,
    _ read: @escaping @Sendable () async throws -> SubscriptionUsageDetails
  ) -> Self {
    Self(subscription: subscription) {
      SubscriptionUsageReading(details: try await read(), legacySnapshot: nil)
    }
  }
}

public enum SubscriptionStatusLineCapture {
  public static let argument = "--capture-subscription-usage"
  public static let notificationName = Notification.Name(
    "io.cmmuu.codex-usage-bar.status-line-captured")
  public static let maximumBytes = 256 * 1024

  public static func command(for subscription: UsageSubscription, executable: URL) -> String? {
    guard subscription.connection == .statusLine else { return nil }
    let escaped = executable.path.replacingOccurrences(of: "'", with: "'\\''")
    return "'\(escaped)' \(argument) \(subscription.rawValue)"
  }

  /// Receives the official CLI status-line JSON, storing just the typed quota projection.
  @discardableResult
  public static func ingest(
    _ input: Data, for subscription: UsageSubscription, observedAt: Date = Date(),
    directory: URL = SharedUsageConfiguration.appCacheDirectory
  ) throws -> SubscriptionUsageDetails? {
    guard input.count <= maximumBytes else { throw SubscriptionUsageError.invalidResponse }
    let details: SubscriptionUsageDetails?
    switch subscription {
    case .claude: details = try ClaudeUsageClient.decodeStatusLine(input, observedAt: observedAt)
    case .antigravity:
      details = try AntigravityUsageClient.decodeStatusLine(input, observedAt: observedAt)
    default: throw SubscriptionUsageError.invalidResponse
    }
    guard let details else { return nil }
    let parent = directory.appendingPathComponent("status-line", isDirectory: true)
    let url = file(for: subscription, directory: directory)
    try FileManager.default.createDirectory(
      at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let lock = Darwin.open(
      url.appendingPathExtension("lock").path,
      O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
    guard lock >= 0 else { throw SubscriptionUsageError.unavailable }
    defer { Darwin.close(lock) }
    guard flock(lock, LOCK_EX) == 0 else { throw SubscriptionUsageError.unavailable }
    // Status lines may redraw after a terminal resize. A repeated reading is not a
    // new server observation and must not make an old quota look fresh.
    if let previous = try? load(for: subscription, directory: directory) {
      if (previous.observedAt ?? .distantPast) >= observedAt
        || (previous.planName == details.planName && previous.quotas == details.quotas)
      {
        return nil
      }
    }
    try JSONEncoder().encode(details).write(to: url, options: .atomic)
    return details
  }

  public static func load(
    for subscription: UsageSubscription, directory: URL = SharedUsageConfiguration.appCacheDirectory
  ) throws -> SubscriptionUsageDetails {
    let data: Data
    do {
      data = try Data(contentsOf: file(for: subscription, directory: directory))
    } catch CocoaError.fileReadNoSuchFile { throw SubscriptionUsageError.waitingForStatusLine }
    guard data.count <= maximumBytes,
      let details = try? JSONDecoder().decode(SubscriptionUsageDetails.self, from: data),
      let normalized = details.normalized, normalized.subscriptionID == subscription.rawValue
    else { throw SubscriptionUsageError.invalidResponse }
    return normalized
  }

  private static func file(for subscription: UsageSubscription, directory: URL) -> URL {
    directory.appendingPathComponent("status-line", isDirectory: true)
      .appendingPathComponent("\(subscription.rawValue).json")
  }
}

enum SubscriptionJSON {
  typealias Object = [String: Any]

  static func object(_ data: Data) throws -> Object {
    guard let value = try? JSONSerialization.jsonObject(with: data), let object = value as? Object
    else { throw SubscriptionUsageError.invalidResponse }
    return object
  }

  static func number(_ value: Any?) -> Double? {
    let number: Double?
    if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
      number = value.doubleValue
    } else if let value = value as? String {
      number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    } else {
      number = nil
    }
    return number.flatMap { $0.isFinite ? $0 : nil }
  }

  static func amount(_ value: Any?) -> Double? {
    number(value).flatMap { $0 >= 0 ? $0 : nil }
  }

  static func date(_ value: Any?) -> Date? {
    if let epoch = number(value), epoch > 0 {
      let seconds = epoch >= 100_000_000_000 ? epoch / 1000 : epoch
      guard seconds >= 946_684_800 && seconds < 4_102_444_800 else { return nil }
      return Date(timeIntervalSince1970: seconds)
    }
    guard let value = value as? String else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions.insert(.withFractionalSeconds)
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions.remove(.withFractionalSeconds)
    return formatter.date(from: value)
  }

  static func quotaKind(_ label: String?) -> UsageQuotaKind {
    switch label {
    case "monthly": return .monthly
    case "weekly": return .weekly
    case "5h": return .fiveHour
    default: return .unknown
    }
  }

  static func details(
    for subscription: UsageSubscription, plan: String?, quotas: [SubscriptionQuota], at time: Date
  ) throws -> SubscriptionUsageDetails {
    let details = SubscriptionUsageDetails(
      subscription: subscription, planName: plan, quotas: quotas, observedAt: time)
    guard !details.quotas.isEmpty else { throw SubscriptionUsageError.unavailable }
    return details
  }
}

enum SubscriptionHTTP {
  private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
      completionHandler(nil)
    }
  }

  static func read(_ url: URL, authorization: String) async throws -> Data {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 8
    configuration.timeoutIntervalForResource = 12
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    let session = URLSession(
      configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(authorization, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw SubscriptionUsageError.invalidResponse
    }
    if http.statusCode == 401 || http.statusCode == 403 {
      throw SubscriptionUsageError.notConnected
    }
    guard http.statusCode == 200 else { throw SubscriptionUsageError.unavailable }
    var data = Data()
    for try await byte in bytes {
      guard data.count < SubscriptionStatusLineCapture.maximumBytes else {
        throw SubscriptionUsageError.invalidResponse
      }
      data.append(byte)
    }
    return data
  }
}

/// Runs fixed, documented read commands without a shell, interactive stdin or raw stderr.
enum SubscriptionCLI {
  static func locate(_ executable: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    let home = FileManager.default.homeDirectoryForCurrentUser
    let fallbacks = [
      "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", home.appendingPathComponent("bin").path,
      home.appendingPathComponent(".local/bin").path,
      home.appendingPathComponent(".npm-global/bin").path,
    ]
    let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + fallbacks
    for path in paths where path.hasPrefix("/") {
      let url = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(executable)
      if FileManager.default.isExecutableFile(atPath: url.path) { return url }
    }
    throw SubscriptionUsageError.missingCLI
  }

  static func run(_ executable: String, _ arguments: [String]) async throws -> Data {
    let url = try locate(executable)
    return try await Task.detached(priority: .utility) {
      let child = try SubscriptionCLIProcess(
        executable: url, arguments: arguments, interactive: false)
      defer { child.close() }
      return try child.collect()
    }.value
  }
}

final class SubscriptionCLIProcess {
  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  private let interactive: Bool
  private let deadline = DispatchTime.now().uptimeNanoseconds + 12_000_000_000
  private var pending = Data()
  private var received = 0
  private static let maximumBytes = 512 * 1024

  init(executable: URL, arguments: [String], interactive: Bool) throws {
    self.interactive = interactive
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    process.standardInput = interactive ? input : FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = [
      executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
      "/usr/bin",
      "/bin", environment["PATH"] ?? "",
    ].joined(separator: ":")
    environment["NO_COLOR"] = "1"
    process.environment = environment
    do { try process.run() } catch { throw SubscriptionUsageError.unavailable }
    try? output.fileHandleForWriting.close()
    if interactive {
      try? input.fileHandleForReading.close()
      _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }
  }

  func close() {
    if interactive { try? input.fileHandleForWriting.close() }
    try? output.fileHandleForReading.close()
    if process.isRunning {
      process.terminate()
      let stop = DispatchTime.now().uptimeNanoseconds + 200_000_000
      while process.isRunning && DispatchTime.now().uptimeNanoseconds < stop { usleep(10_000) }
      if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
    }
  }

  func collect() throws -> Data {
    var data = Data()
    while let chunk = try readChunk() { data.append(chunk) }
    while process.isRunning {
      try checkDeadline()
      usleep(10_000)
    }
    guard process.terminationStatus == 0 else { throw SubscriptionUsageError.unavailable }
    return data
  }

  func rpc(id: Int, method: String, params: SubscriptionJSON.Object = [:]) throws
    -> SubscriptionJSON.Object
  {
    try checkDeadline()
    let body = try JSONSerialization.data(withJSONObject: [
      "jsonrpc": "2.0", "id": id, "method": method, "params": params,
    ])
    let message = Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body
    do { try input.fileHandleForWriting.write(contentsOf: message) } catch {
      throw SubscriptionUsageError.unavailable
    }
    while true {
      let result = try SubscriptionJSON.object(readFrame())
      guard (result["id"] as? Int) == id else { continue }
      guard let payload = result["result"] as? SubscriptionJSON.Object else {
        throw SubscriptionUsageError.unavailable
      }
      return payload
    }
  }

  private func readFrame() throws -> Data {
    let separator = Data("\r\n\r\n".utf8)
    while pending.range(of: separator) == nil {
      guard pending.count <= 4096, let data = try readChunk() else {
        throw SubscriptionUsageError.invalidResponse
      }
      pending.append(data)
    }
    guard let header = pending.range(of: separator),
      let text = String(data: pending[..<header.lowerBound], encoding: .utf8),
      let lengthLine = text.components(separatedBy: "\r\n").first(where: {
        $0.lowercased().hasPrefix("content-length:")
      }),
      let length = Int(
        lengthLine.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)),
      length > 0, length <= Self.maximumBytes
    else { throw SubscriptionUsageError.invalidResponse }
    let end = header.upperBound + length
    while pending.count < end {
      guard let data = try readChunk() else { throw SubscriptionUsageError.invalidResponse }
      pending.append(data)
    }
    let body = Data(pending[header.upperBound..<end])
    pending = Data(pending.dropFirst(end))
    return body
  }

  private func readChunk() throws -> Data? {
    let fd = output.fileHandleForReading.fileDescriptor
    while true {
      try checkDeadline()
      var item = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
      let ready = Darwin.poll(&item, 1, 100)
      if ready == 0 || (ready == -1 && errno == EINTR) { continue }
      guard ready > 0 else { throw SubscriptionUsageError.unavailable }
      let data = output.fileHandleForReading.availableData
      if data.isEmpty { return nil }
      received += data.count
      guard received <= Self.maximumBytes else { throw SubscriptionUsageError.invalidResponse }
      return data
    }
  }

  private func checkDeadline() throws {
    guard DispatchTime.now().uptimeNanoseconds < deadline else {
      throw SubscriptionUsageError.timedOut
    }
  }
}
