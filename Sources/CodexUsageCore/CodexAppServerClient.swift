import Darwin
import Foundation

public actor CodexAppServerClient {
  private let explicitExecutableURL: URL?
  private let timeout: TimeInterval

  public init(executableURL: URL? = nil, timeout: TimeInterval = 10) {
    explicitExecutableURL = executableURL
    self.timeout = timeout
  }

  public func fetchUsage() async throws -> UsageSnapshot {
    let executableURL = try explicitExecutableURL ?? CodexExecutableLocator.resolve()
    let timeout = timeout

    let responses = try await Task.detached(priority: .utility) {
      try CodexAppServerProbe(executableURL: executableURL).run(timeout: timeout)
    }.value

    guard let accountData = responses[1] else {
      throw CodexAppServerClientError.missingResponse("account/read")
    }
    guard let rateLimitsData = responses[2] else {
      throw CodexAppServerClientError.missingResponse("account/rateLimits/read")
    }

    let decoder = JSONDecoder()
    let accountEnvelope = try decoder.decode(
      RPCEnvelope<AccountReadResult>.self,
      from: accountData
    )
    if let error = accountEnvelope.error {
      throw error
    }

    let rateLimitsEnvelope = try decoder.decode(
      RPCEnvelope<RateLimitsReadResult>.self,
      from: rateLimitsData
    )
    if let error = rateLimitsEnvelope.error {
      throw error
    }
    guard let rateLimits = rateLimitsEnvelope.result else {
      throw CodexAppServerClientError.missingResult("account/rateLimits/read")
    }

    if accountEnvelope.result?.requiresOpenaiAuth == true,
      accountEnvelope.result?.account == nil
    {
      throw CodexAppServerClientError.notSignedIn
    }

    return try WeeklyUsageSelector.select(
      from: rateLimits,
      accountPlanType: accountEnvelope.result?.account?.planType
    )
  }
}

enum CodexAppServerClientError: LocalizedError {
  case launchFailed(String)
  case timeout
  case terminated(Int32)
  case missingResponse(String)
  case missingResult(String)
  case notSignedIn
  case invalidProtocol

  var errorDescription: String? {
    switch self {
    case .launchFailed(let message):
      return "启动 Codex app-server 失败：\(message)"
    case .timeout:
      return "读取 Codex 限额超时"
    case .terminated(let status):
      return "Codex app-server 已退出，状态码：\(status)"
    case .missingResponse(let method):
      return "Codex app-server 未返回 \(method)"
    case .missingResult(let method):
      return "Codex app-server 的 \(method) 响应缺少结果"
    case .notSignedIn:
      return "Codex 当前未登录 ChatGPT"
    case .invalidProtocol:
      return "Codex app-server 返回了无法解析的数据"
    }
  }
}

private struct RPCResponseHeader: Decodable {
  let id: Int?
  let error: RPCErrorPayload?
}

private struct CodexAppServerProbe: Sendable {
  let executableURL: URL

  func run(timeout: TimeInterval) throws -> [Int: Data] {
    let process = Process()
    let standardInput = Pipe()
    let standardOutput = Pipe()

    process.executableURL = executableURL
    process.arguments = ["app-server", "--stdio"]
    process.standardInput = standardInput
    process.standardOutput = standardOutput
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw CodexAppServerClientError.launchFailed(error.localizedDescription)
    }

    let inputHandle = standardInput.fileHandleForWriting
    let outputHandle = standardOutput.fileHandleForReading

    defer {
      try? inputHandle.close()
      try? outputHandle.close()
      stop(process)
    }

    let payload = """
      {"method":"initialize","id":0,"params":{"clientInfo":{"name":"codex-usage-bar","title":"Codex Usage Bar","version":"0.1.0"}}}
      {"method":"initialized","params":{}}
      {"method":"account/read","id":1,"params":{"refreshToken":false}}
      {"method":"account/rateLimits/read","id":2}

      """

    do {
      try inputHandle.write(contentsOf: Data(payload.utf8))
    } catch {
      throw CodexAppServerClientError.launchFailed(error.localizedDescription)
    }

    let deadline = Date().addingTimeInterval(timeout)
    var buffer = Data()
    var responses: [Int: Data] = [:]
    let outputDescriptor = outputHandle.fileDescriptor
    let currentFlags = fcntl(outputDescriptor, F_GETFL)
    guard currentFlags >= 0,
      fcntl(outputDescriptor, F_SETFL, currentFlags | O_NONBLOCK) >= 0
    else {
      throw CodexAppServerClientError.invalidProtocol
    }
    var descriptor = pollfd(
      fd: outputDescriptor,
      events: Int16(POLLIN | POLLHUP | POLLERR),
      revents: 0
    )

    while Date() < deadline {
      let remainingMilliseconds = max(
        1,
        min(250, Int(deadline.timeIntervalSinceNow * 1_000))
      )
      descriptor.revents = 0
      let pollResult = Darwin.poll(&descriptor, 1, Int32(remainingMilliseconds))

      if pollResult < 0 {
        if errno == EINTR {
          continue
        }
        throw CodexAppServerClientError.invalidProtocol
      }

      if pollResult > 0,
        descriptor.revents & Int16(POLLIN | POLLHUP) != 0
      {
        var bytes = [UInt8](repeating: 0, count: 16_384)
        let byteCount = bytes.withUnsafeMutableBytes {
          Darwin.read(outputDescriptor, $0.baseAddress, $0.count)
        }
        if byteCount > 0 {
          buffer.append(contentsOf: bytes.prefix(byteCount))
          try consumeLines(from: &buffer, into: &responses)
          if responses[1] != nil, responses[2] != nil {
            return responses
          }
        } else if byteCount < 0, errno != EAGAIN, errno != EWOULDBLOCK,
          errno != EINTR
        {
          throw CodexAppServerClientError.invalidProtocol
        }
      }

      if !process.isRunning {
        if responses[1] != nil, responses[2] != nil {
          return responses
        }
        throw CodexAppServerClientError.terminated(process.terminationStatus)
      }
    }

    throw CodexAppServerClientError.timeout
  }

  private func consumeLines(
    from buffer: inout Data,
    into responses: inout [Int: Data]
  ) throws {
    while let newlineIndex = buffer.firstIndex(of: 0x0A) {
      let line = Data(buffer[..<newlineIndex])
      buffer.removeSubrange(...newlineIndex)

      guard !line.isEmpty else {
        continue
      }

      let header: RPCResponseHeader
      do {
        header = try JSONDecoder().decode(RPCResponseHeader.self, from: line)
      } catch {
        continue
      }

      if header.id == 0, let error = header.error {
        throw error
      }
      if let id = header.id, id == 1 || id == 2 {
        responses[id] = line
      }
    }
  }

  private func stop(_ process: Process) {
    guard process.isRunning else {
      return
    }

    process.terminate()
    let gracefulDeadline = Date().addingTimeInterval(1)
    while process.isRunning, Date() < gracefulDeadline {
      usleep(10_000)
    }
    if process.isRunning {
      kill(process.processIdentifier, SIGKILL)
    }
    process.waitUntilExit()
  }
}
