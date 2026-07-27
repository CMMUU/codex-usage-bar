import CodexUsageCore
import Combine
import Foundation
import ServiceManagement

@MainActor
final class UsageViewModel: ObservableObject {
  @Published private(set) var snapshot: UsageSnapshot?
  @Published private(set) var isRefreshing = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var lastUpdated: Date?
  @Published private(set) var launchAtLoginEnabled = false
  @Published private(set) var launchAtLoginError: String?

  private let client: CodexAppServerClient
  private var activated = false
  private var refreshLoop: Task<Void, Never>?

  init(client: CodexAppServerClient = CodexAppServerClient()) {
    self.client = client
  }

  deinit {
    refreshLoop?.cancel()
  }

  var menuBarText: String {
    if let snapshot {
      return "Codex \(Int(snapshot.usedPercent.rounded()))%"
    }
    return isRefreshing ? "Codex …" : "Codex --"
  }

  var planDisplayName: String {
    guard let plan = snapshot?.planType, !plan.isEmpty else {
      return "未知"
    }
    return plan.prefix(1).uppercased() + plan.dropFirst()
  }

  var resetDisplayText: String {
    guard let resetDate = snapshot?.resetsAt else {
      return "未知"
    }
    return Self.resetDateFormatter.string(from: resetDate)
  }

  var lastUpdatedDisplayText: String {
    guard let lastUpdated else {
      return "尚未刷新"
    }
    return Self.lastUpdatedFormatter.string(from: lastUpdated)
  }

  func activate() async {
    guard !activated else {
      return
    }
    activated = true
    refreshLaunchAtLoginStatus()
    await refresh()
    startRefreshLoop()
  }

  func refreshIfStale(maxAge: TimeInterval = 60) async {
    if let lastUpdated, Date().timeIntervalSince(lastUpdated) < maxAge {
      return
    }
    await refresh()
  }

  func refresh() async {
    guard !isRefreshing else {
      return
    }

    isRefreshing = true
    defer {
      isRefreshing = false
    }

    do {
      snapshot = try await client.fetchUsage()
      lastUpdated = Date()
      errorMessage = nil
    } catch {
      errorMessage =
        (error as? LocalizedError)?.errorDescription
        ?? error.localizedDescription
    }
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    launchAtLoginError = nil

    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      launchAtLoginError = "更新登录启动设置失败：\(error.localizedDescription)"
    }

    refreshLaunchAtLoginStatus()
  }

  func loadDocumentationPreview() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current

    snapshot = UsageSnapshot(
      usedPercent: 64,
      windowDurationMinutes: 10_080,
      resetsAt: calendar.date(
        from: DateComponents(
          year: 2026,
          month: 8,
          day: 2,
          hour: 12,
          minute: 30
        )
      ),
      planType: "pro",
      limitName: "Codex",
      reachedLimitType: nil
    )
    lastUpdated = calendar.date(
      from: DateComponents(
        year: 2026,
        month: 7,
        day: 27,
        hour: 10,
        minute: 24,
        second: 18
      )
    )
    errorMessage = nil
    isRefreshing = false
  }

  private func startRefreshLoop() {
    guard refreshLoop == nil else {
      return
    }

    refreshLoop = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: 300_000_000_000)
        } catch {
          return
        }
        guard let self else {
          return
        }
        await self.refresh()
      }
    }
  }

  private func refreshLaunchAtLoginStatus() {
    launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
  }

  private static let resetDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日 HH:mm"
    return formatter
  }()

  private static let lastUpdatedFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()
}
