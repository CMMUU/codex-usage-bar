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
  @Published private(set) var selectedSubscription: UsageSubscription
  @Published private(set) var displayLanguage: AppLanguage
  @Published private(set) var isLanguageSwitching = false

  private let client: CodexAppServerClient
  private let kimiClient: KimiUsageClient
  private let sharedUsageStore: SharedUsageStore
  private let sharedWidgetPreferencesStore: SharedWidgetPreferencesStore
  private let localUsageServer: LocalUsageSnapshotServer
  private let languageDefaults: UserDefaults
  private var languageTransition: LanguageTransitionState
  private var activated = false
  private var refreshLoop: Task<Void, Never>?

  init(
    client: CodexAppServerClient = CodexAppServerClient(),
    kimiClient: KimiUsageClient = KimiUsageClient(),
    sharedUsageStore: SharedUsageStore = SharedUsageStore(),
    sharedWidgetPreferencesStore: SharedWidgetPreferencesStore =
      SharedWidgetPreferencesStore(),
    localUsageServer: LocalUsageSnapshotServer = LocalUsageSnapshotServer(),
    displayLanguage: AppLanguage? = nil,
    languageDefaults: UserDefaults = .standard
  ) {
    self.client = client
    self.kimiClient = kimiClient
    self.sharedUsageStore = sharedUsageStore
    self.sharedWidgetPreferencesStore = sharedWidgetPreferencesStore
    self.localUsageServer = localUsageServer
    self.languageDefaults = languageDefaults
    let initialLanguage =
      displayLanguage
      ?? AppLanguage.resolve(
        languageDefaults.string(forKey: AppLanguage.storageKey)
      )
    self.displayLanguage = initialLanguage
    languageTransition = LanguageTransitionState(current: initialLanguage)
    selectedSubscription = UsageSubscription.resolve(
      sharedWidgetPreferencesStore.load()?.subscriptionID
    )
  }

  deinit {
    refreshLoop?.cancel()
    localUsageServer.stop()
  }

  var menuBarText: String {
    let name = selectedSubscription.displayName
    if let snapshot {
      return "\(name) \(Int(snapshot.usedPercent.rounded()))%"
    }
    return isRefreshing ? "\(name) …" : "\(name) --"
  }

  /// The language that will be applied after the in-flight refresh finishes.
  /// The current display language remains unchanged until then.
  var pendingDisplayLanguage: AppLanguage? {
    languageTransition.pending
  }

  func selectSubscription(_ subscription: UsageSubscription) {
    guard subscription != selectedSubscription else {
      return
    }
    selectedSubscription = subscription
    snapshot = nil
    lastUpdated = nil
    errorMessage = nil
    persistWidgetPreferences()
    Task {
      await refresh()
    }
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
    let result = languageTransition.request(
      language,
      whileRefreshing: isRefreshing
    )

    switch result {
    case .unchanged, .ignored:
      isLanguageSwitching = languageTransition.isWaitingForRefresh
    case .queued:
      isLanguageSwitching = true
    case .applied(let language):
      commitDisplayLanguage(language)
      isLanguageSwitching = false
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
      applyPendingDisplayLanguageIfNeeded()
    }

    do {
      let fetchedSnapshot: UsageSnapshot
      switch selectedSubscription {
      case .codex:
        fetchedSnapshot = try await client.fetchUsage()
      case .k3:
        fetchedSnapshot = try await kimiClient.fetchUsage()
      }
      let updatedAt = Date()
      snapshot = fetchedSnapshot
      lastUpdated = updatedAt
      errorMessage = nil
      if let pendingLanguage = takePendingDisplayLanguage() {
        updateDisplayLanguageState(pendingLanguage)
      }
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

  func loadDocumentationPreview(
    subscription: UsageSubscription = .codex
  ) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current

    selectedSubscription = subscription
    switch subscription {
    case .codex:
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
        reachedLimitType: nil,
        fiveHourWindow: UsageSubWindow(
          usedPercent: 45,
          windowDurationMinutes: 300,
          resetsAt: calendar.date(
            from: DateComponents(
              year: 2026,
              month: 7,
              day: 27,
              hour: 15,
              minute: 30
            )
          )
        )
      )
    case .k3:
      snapshot = UsageSnapshot(
        usedPercent: 21,
        windowDurationMinutes: 0,
        resetsAt: calendar.date(
          from: DateComponents(
            year: 2026,
            month: 7,
            day: 31,
            hour: 11,
            minute: 22
          )
        ),
        planType: "intermediate",
        limitName: "K3",
        reachedLimitType: nil,
        fiveHourWindow: UsageSubWindow(
          usedPercent: 50,
          windowDurationMinutes: 300,
          resetsAt: calendar.date(
            from: DateComponents(
              year: 2026,
              month: 7,
              day: 31,
              hour: 10,
              minute: 22
            )
          )
        )
      )
    }
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

  private func persistWidgetPreferences() {
    do {
      try sharedWidgetPreferencesStore.save(
        SharedWidgetPreferences(
          languageCode: displayLanguage.rawValue,
          subscriptionID: selectedSubscription.rawValue
        )
      )
    } catch {
      fputs("Widget preferences update failed: \(error)\n", stderr)
    }
  }

  private func applyPendingDisplayLanguageIfNeeded() {
    if let language = takePendingDisplayLanguage() {
      commitDisplayLanguage(language)
    }
  }

  private func takePendingDisplayLanguage() -> AppLanguage? {
    guard languageTransition.isWaitingForRefresh else {
      return nil
    }

    let result = languageTransition.finishRefreshing()
    isLanguageSwitching = languageTransition.isWaitingForRefresh
    if case .applied(let language) = result {
      return language
    }
    return nil
  }

  private func updateDisplayLanguageState(_ language: AppLanguage) {
    displayLanguage = language
    languageDefaults.set(language.rawValue, forKey: AppLanguage.storageKey)
    localUsageServer.updateLanguage(language.rawValue)
    persistWidgetPreferences()
  }

  private func commitDisplayLanguage(_ language: AppLanguage) {
    updateDisplayLanguageState(language)

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
      languageCode: displayLanguage.rawValue,
      subscriptionID: selectedSubscription.rawValue,
      fiveHourUsedPercent: snapshot.fiveHourWindow?.usedPercent,
      fiveHourResetsAt: snapshot.fiveHourWindow?.resetsAt
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
