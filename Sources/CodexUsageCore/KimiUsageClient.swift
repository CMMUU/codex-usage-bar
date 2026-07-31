import Foundation

public struct KimiCredentials: Codable, Equatable, Sendable {
  public let accessToken: String
  public let refreshToken: String
  public let expiresAt: TimeInterval
  public let expiresIn: TimeInterval?
  public let scope: String?
  public let tokenType: String?

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresAt = "expires_at"
    case expiresIn = "expires_in"
    case scope
    case tokenType = "token_type"
  }

  public init(
    accessToken: String,
    refreshToken: String,
    expiresAt: TimeInterval,
    expiresIn: TimeInterval? = nil,
    scope: String? = nil,
    tokenType: String? = nil
  ) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt
    self.expiresIn = expiresIn
    self.scope = scope
    self.tokenType = tokenType
  }

  public func isAccessTokenValid(
    at date: Date = Date(),
    leeway: TimeInterval = 60
  ) -> Bool {
    date.timeIntervalSince1970 + leeway < expiresAt
  }
}

public enum KimiUsageClientError: LocalizedError, Equatable {
  case credentialsMissing
  case unauthorized
  case refreshFailed(String)
  case requestFailed(Int)
  case invalidResponse

  public var errorDescription: String? {
    switch self {
    case .credentialsMissing:
      return "未找到 kimi-code 登录凭证，请先运行 kimi CLI 完成登录"
    case .unauthorized:
      return "K3 登录状态已失效，请重新运行 kimi CLI 登录"
    case .refreshFailed(let detail):
      return "K3 凭证刷新失败：\(detail)"
    case .requestFailed(let status):
      return "K3 额度接口请求失败，状态码：\(status)"
    case .invalidResponse:
      return "K3 额度数据无法解析"
    }
  }
}

public enum KimiUsageMapper {
  private static let fiveHourWindowMinutes = 5 * 60
  private static let fiveHourWindowRange = (4 * 60 + 30)...(5 * 60 + 30)

  public static func snapshot(from data: Data) throws -> UsageSnapshot {
    guard let payload = try? JSONDecoder().decode(KimiUsagesPayload.self, from: data) else {
      throw KimiUsageClientError.invalidResponse
    }
    guard let usage = payload.usage,
      let limit = usage.limit.flatMap(Double.init), limit > 0,
      let used = usage.used.flatMap(Double.init)
    else {
      throw KimiUsageClientError.invalidResponse
    }

    return UsageSnapshot(
      usedPercent: min(100, max(0, used / limit * 100)),
      // The top-level quota does not declare its window length.
      windowDurationMinutes: 0,
      resetsAt: parseResetTime(usage.resetTime),
      planType: planName(from: payload.user?.membership?.level),
      limitName: "K3",
      reachedLimitType: nil,
      fiveHourWindow: fiveHourWindow(from: payload.limits)
    )
  }

  private static func fiveHourWindow(
    from limits: [KimiUsagesPayload.LimitEntry]?
  ) -> UsageSubWindow? {
    guard let entry = limits?.first(where: {
      $0.window?.timeUnit == "TIME_UNIT_MINUTE"
        && $0.window?.duration.map(fiveHourWindowRange.contains) == true
    }), let detail = entry.detail,
      let limit = detail.limit.flatMap(Double.init), limit > 0,
      let used = detail.used.flatMap(Double.init)
    else {
      return nil
    }

    return UsageSubWindow(
      usedPercent: min(100, max(0, used / limit * 100)),
      windowDurationMinutes: entry.window?.duration ?? fiveHourWindowMinutes,
      resetsAt: parseResetTime(detail.resetTime)
    )
  }

  private static func parseResetTime(_ rawValue: String?) -> Date? {
    guard let rawValue else {
      return nil
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: rawValue) {
      return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: rawValue)
  }

  private static func planName(from level: String?) -> String? {
    guard let level, !level.isEmpty else {
      return nil
    }
    if level.hasPrefix("LEVEL_") {
      return String(level.dropFirst("LEVEL_".count)).lowercased()
    }
    return level.lowercased()
  }
}

private struct KimiUsagesPayload: Decodable {
  struct User: Decodable {
    struct Membership: Decodable {
      let level: String?
    }
    let membership: Membership?
  }

  struct Quota: Decodable {
    let limit: String?
    let used: String?
    let remaining: String?
    let resetTime: String?
  }

  struct LimitEntry: Decodable {
    struct Window: Decodable {
      let duration: Int?
      let timeUnit: String?
    }
    let window: Window?
    let detail: Quota?
  }

  let user: User?
  let usage: Quota?
  let limits: [LimitEntry]?
}

public actor KimiUsageClient {
  private static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
  private static let tokenEndpoint = URL(
    string: "https://auth.kimi.com/api/oauth/token"
  )!
  private static let usageEndpoint = URL(
    string: "https://api.kimi.com/coding/v1/usages"
  )!

  private let credentialsFileURL: URL
  private let session: URLSession
  private let timeout: TimeInterval

  public init(
    credentialsFileURL: URL? = nil,
    session: URLSession = .shared,
    timeout: TimeInterval = 15
  ) {
    self.credentialsFileURL =
      credentialsFileURL ?? Self.defaultCredentialsFileURL()
    self.session = session
    self.timeout = timeout
  }

  public static func defaultCredentialsFileURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(
        ".kimi-code/credentials/kimi-code.json",
        isDirectory: false
      )
  }

  public func fetchUsage() async throws -> UsageSnapshot {
    var credentials = try loadCredentials()
    if !credentials.isAccessTokenValid() {
      credentials = try await refresh(credentials)
    }

    do {
      return try await requestUsage(accessToken: credentials.accessToken)
    } catch KimiUsageClientError.unauthorized {
      credentials = try await refresh(credentials)
      return try await requestUsage(accessToken: credentials.accessToken)
    }
  }

  func loadCredentials() throws -> KimiCredentials {
    guard let data = try? Data(contentsOf: credentialsFileURL),
      let credentials = try? JSONDecoder().decode(
        KimiCredentials.self,
        from: data
      )
    else {
      throw KimiUsageClientError.credentialsMissing
    }
    return credentials
  }

  private func refresh(
    _ credentials: KimiCredentials
  ) async throws -> KimiCredentials {
    var request = URLRequest(url: Self.tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue(
      "application/x-www-form-urlencoded",
      forHTTPHeaderField: "Content-Type"
    )
    request.timeoutInterval = timeout
    request.httpBody = Data(
      [
        "grant_type=refresh_token",
        "refresh_token=\(Self.formEncode(credentials.refreshToken))",
        "client_id=\(Self.clientID)",
      ]
      .joined(separator: "&")
      .utf8
    )

    let (data, response) = try await session.data(for: request)
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
    guard statusCode == 200 else {
      throw KimiUsageClientError.refreshFailed("\(statusCode)")
    }

    struct RefreshResponse: Decodable {
      let access_token: String
      let refresh_token: String
      let expires_in: TimeInterval
      let scope: String?
      let token_type: String?
    }
    guard let parsed = try? JSONDecoder().decode(
      RefreshResponse.self,
      from: data
    ) else {
      throw KimiUsageClientError.refreshFailed("invalid response")
    }

    let updated = KimiCredentials(
      accessToken: parsed.access_token,
      refreshToken: parsed.refresh_token,
      expiresAt: Date().timeIntervalSince1970 + parsed.expires_in,
      expiresIn: parsed.expires_in,
      scope: parsed.scope ?? credentials.scope,
      tokenType: parsed.token_type ?? credentials.tokenType
    )
    try saveCredentials(updated)
    return updated
  }

  private func saveCredentials(_ credentials: KimiCredentials) throws {
    let data = try JSONEncoder().encode(credentials)
    try data.write(to: credentialsFileURL, options: [.atomic])
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: credentialsFileURL.path
    )
  }

  private func requestUsage(accessToken: String) async throws -> UsageSnapshot {
    var request = URLRequest(url: Self.usageEndpoint)
    request.setValue(
      "Bearer \(accessToken)",
      forHTTPHeaderField: "Authorization"
    )
    request.timeoutInterval = timeout

    let (data, response) = try await session.data(for: request)
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
    if statusCode == 401 {
      throw KimiUsageClientError.unauthorized
    }
    guard statusCode == 200 else {
      throw KimiUsageClientError.requestFailed(statusCode)
    }
    return try KimiUsageMapper.snapshot(from: data)
  }

  private static func formEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}
