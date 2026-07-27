import CodexUsageCore
import CodexUsageShared
import Combine
import Foundation
import ServiceManagement
import WidgetKit

@MainActor
final class UsageViewModel: ObservableObject {
  @Published private(set) var snapshot: UsageSnapshot?
  @Published private(set) var isRefreshing = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var lastUpdated: Date?
  @Published private(set) var launchAtLoginEnabled = false
  @Published private(set) var launchAtLoginErrorDetails: String?

  private let client: CodexAppServerClient
  private let sharedUsageStore: SharedUsageStore
  private let sharedWidgetPreferencesStore: SharedWidgetPreferencesStore
  private let localUsageServer: LocalUsageSnapshotServer
  private var displayLanguage: AppLanguage
  private var activated = false
  private var refreshLoop: Task<Void, Never>?

  init(
    client: CodexAppServerClient = CodexAppServerClient(),
    sharedUsageStore: SharedUsageStore = SharedUsageStore(),
    sharedWidgetPreferencesStore: SharedWidgetPreferencesStore =
      SharedWidgetPreferencesStore(),
    localUsageServer: LocalUsageSnapshotServer = LocalUsageSnapshotServer(),
    displayLanguage: AppLanguage = .systemDefault
  ) {
    self.client = client
    self.sharedUsageStore = sharedUsageStore
    self.sharedWidgetPreferencesStore = sharedWidgetPreferencesStore
    self.localUsageServer = localUsageServer
    self.displayLanguage = displayLanguage
  }

  deinit {
    refreshLoop?.cancel()
    localUsageServer.stop()
  }

  var menuBarText: String {
    if let snapshot {
      return "Codex \(Int(snapshot.usedPercent.rounded()))%"
    }
    return isRefreshing ? "Codex …" : "Codex --"
  }

  func planDisplayName(for language: AppLanguage) -> String {
    guard let plan = snapshot?.planType, !plan.isEmpty else {
      return language.text(.unknown)
    }
    return plan.prefix(1).uppercased() + plan.dropFirst()
  }

  func resetDisplayText(for language: AppLanguage) -> String {
    language.resetDisplayText(snapshot?.resetsAt)
  }

  func lastUpdatedDisplayText(for language: AppLanguage) -> String {
    language.lastUpdatedDisplayText(lastUpdated)
  }

  func errorDisplayText(for language: AppLanguage) -> String? {
    errorMessage.map(language.localizedErrorMessage)
  }

  func launchAtLoginErrorText(for language: AppLanguage) -> String? {
    guard let launchAtLoginErrorDetails else {
      return nil
    }
    return
      "\(language.text(.launchAtLoginUpdateFailed)): "
      + launchAtLoginErrorDetails
  }

  func setDisplayLanguage(_ language: AppLanguage) {
    let languageChanged = displayLanguage != language
    displayLanguage = language
    localUsageServer.updateLanguage(language.rawValue)

    do {
      try sharedWidgetPreferencesStore.save(
        SharedWidgetPreferences(languageCode: language.rawValue)
      )
    } catch {
      fputs("Widget language update failed: \(error)\n", stderr)
    }

    guard languageChanged else {
      WidgetCenter.shared.reloadTimelines(
        ofKind: SharedUsageConfiguration.widgetKind
      )
      return
    }

    if let snapshot {
      publishWidgetSnapshot(
        snapshot,
        updatedAt: lastUpdated ?? Date()
      )
    } else {
      WidgetCenter.shared.reloadTimelines(
        ofKind: SharedUsageConfiguration.widgetKind
      )
    }
  }

  func activate() async {
    guard !activated else {
      return
    }
    activated = true
    localUsageServer.start()
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
      let fetchedSnapshot = try await client.fetchUsage()
      let updatedAt = Date()
      snapshot = fetchedSnapshot
      lastUpdated = updatedAt
      errorMessage = nil
      publishWidgetSnapshot(fetchedSnapshot, updatedAt: updatedAt)
    } catch {
      errorMessage =
        (error as? LocalizedError)?.errorDescription
        ?? error.localizedDescription
    }
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    launchAtLoginErrorDetails = nil

    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      launchAtLoginErrorDetails = error.localizedDescription
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

  private func publishWidgetSnapshot(
    _ snapshot: UsageSnapshot,
    updatedAt: Date
  ) {
    let sharedSnapshot = SharedUsageSnapshot(
      usedPercent: snapshot.usedPercent,
      resetsAt: snapshot.resetsAt,
      planType: snapshot.planType,
      limitName: snapshot.limitName,
      updatedAt: updatedAt,
      languageCode: displayLanguage.rawValue
    )

    localUsageServer.update(sharedSnapshot)
    do {
      try sharedUsageStore.save(sharedSnapshot)
    } catch {
      fputs("Widget snapshot update failed: \(error)\n", stderr)
    }
    WidgetCenter.shared.reloadTimelines(
      ofKind: SharedUsageConfiguration.widgetKind
    )
  }

}
