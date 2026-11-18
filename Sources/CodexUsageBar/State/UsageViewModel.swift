import CodexUsageCore
import CodexUsageShared
import Combine
import Foundation
import ServiceManagement
import WidgetKit

@MainActor
final class UsageViewModel: ObservableObject {
  @Published private(set) var snapshot: UsageSnapshot?
  @Published private(set) var subscriptionDetails: SubscriptionUsageDetails?
  @Published private(set) var isRefreshing = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var subscriptionError: SubscriptionUsageError?
  @Published private(set) var hasSubscriptionKey = false
  @Published private(set) var lastUpdated: Date?
  @Published private(set) var launchAtLoginEnabled = false
  @Published private(set) var launchAtLoginErrorDetails: String?
  @Published private(set) var selectedSubscription: UsageSubscription
  @Published private(set) var displayLanguage: AppLanguage
  @Published private(set) var isLanguageSwitching = false
  @Published private(set) var widgetSyncFailed = false

  private let adapters: [UsageSubscription: SubscriptionUsageAdapter]
  private let credentials: SubscriptionCredentialStore
  private let sharedWidgetStateStore: SharedWidgetStateStore
  private let sharedUsageStore: SharedUsageStore
  private let sharedWidgetPreferencesStore: SharedWidgetPreferencesStore
  private let localUsageServer: LocalUsageSnapshotServer
  private let languageDefaults: UserDefaults
  private let appCacheStore = SharedWidgetStateStore(
    directoryURL: SharedUsageConfiguration.appCacheDirectory)
  private var lastPublishedWidgetState: SharedWidgetState?
  private var isRecoveringWidgetAfterUpgrade = false
  private var languageTransition: LanguageTransitionState
  private var activated = false
  private var refreshLoop: Task<Void, Never>?
  private var selectionRevision = 0
  private var refreshRequested = false

  init(
    client: CodexAppServerClient = CodexAppServerClient(),
    kimiClient: KimiUsageClient = KimiUsageClient(),
    sharedWidgetStateStore: SharedWidgetStateStore = SharedWidgetStateStore(),
    sharedUsageStore: SharedUsageStore = SharedUsageStore(),
    sharedWidgetPreferencesStore: SharedWidgetPreferencesStore =
      SharedWidgetPreferencesStore(),
    localUsageServer: LocalUsageSnapshotServer = LocalUsageSnapshotServer(),
    displayLanguage: AppLanguage? = nil,
    languageDefaults: UserDefaults = .standard
  ) {
    let credentials = SubscriptionCredentialStore()
    self.credentials = credentials
    adapters = SubscriptionUsageAdapter.defaults(
      codex: client, kimi: kimiClient, credentials: credentials)
    self.sharedWidgetStateStore = sharedWidgetStateStore
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
      languageDefaults.string(forKey: UsageSubscription.storageKey)
        ?? sharedWidgetStateStore.load()?.subscriptionID
        ?? sharedWidgetPreferencesStore.load()?.subscriptionID
    )
    loadConnectionStatus()
    restoreCachedSnapshot()
    if sharedWidgetPreferencesStore.load()?.subscriptionID == "k3" {
      persistWidgetPreferences()
    }
  }

  deinit {
    refreshLoop?.cancel()
    localUsageServer.stop()
  }

  private var displaySnapshot: SharedUsageSnapshot? {
    snapshot?.shared(
      subscription: selectedSubscription, language: displayLanguage,
      updatedAt: lastUpdated ?? Date()
    )
  }

  var displayDetails: SubscriptionUsageDetails {
    if let subscriptionDetails { return subscriptionDetails }
    if let displaySnapshot {
      return SubscriptionUsageDetails(legacy: displaySnapshot, subscription: selectedSubscription)
    }
    return SubscriptionUsageDetails(
      subscription: selectedSubscription,
      availability: selectedSubscription.connection == .apiKey && !hasSubscriptionKey
        ? .notConnected : .waiting)
  }

  var primaryQuotaKind: UsageQuotaKind {
    displayDetails.primaryQuota?.kind ?? (selectedSubscription == .codex ? .weekly : .unknown)
  }

  var menuBarText: String {
    let name = selectedSubscription.displayName(in: displayLanguage)
    if let value = displayDetails.primaryQuota?.menuBarValue(in: displayLanguage) {
      return "\(name) \(value)"
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
    selectionRevision += 1
    clearReading()
    loadConnectionStatus()
    restoreCachedSnapshot()
    persistWidgetPreferences()
    publishWidgetState()
    Task {
      await refresh()
    }
  }

  @discardableResult
  func connectWithKey(_ key: String) -> Bool {
    do {
      try credentials.save(key, for: selectedSubscription)
      hasSubscriptionKey = true
      connectionDidChange()
      return true
    } catch {
      subscriptionError = .keychain
      return false
    }
  }

  func disconnectKey() {
    do {
      try credentials.remove(for: selectedSubscription)
      hasSubscriptionKey = false
      connectionDidChange()
    } catch {
      subscriptionError = .keychain
    }
  }

  private func loadConnectionStatus() {
    hasSubscriptionKey = (try? credentials.load(for: selectedSubscription)) != nil
  }

  private func connectionDidChange() {
    selectionRevision += 1
    clearReading()
    publishWidgetState()
    if hasSubscriptionKey {
      Task { await refresh() }
    }
  }

  private func clearReading() {
    snapshot = nil
    subscriptionDetails = nil
    lastUpdated = nil
    errorMessage = nil
    subscriptionError = nil
  }

  func statusLineDidChange(provider: String?) {
    guard selectedSubscription.connection == .statusLine,
      UsageSubscription.recognized(provider) == selectedSubscription
    else { return }
    if isRefreshing {
      refreshRequested = true
    } else {
      Task { await refresh() }
    }
  }

  func errorDisplayText(for language: AppLanguage) -> String? {
    if let subscriptionError { return subscriptionError.text(in: language) }
    return errorMessage.map(language.localizedErrorMessage)
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
    let widgetBuild = WidgetUpgradeRecovery.pendingBuild(defaults: languageDefaults)
    isRecoveringWidgetAfterUpgrade = widgetBuild != nil
    localUsageServer.start()
    publishWidgetState()
    refreshLaunchAtLoginStatus()
    if let widgetBuild {
      let recovered = await WidgetUpgradeRecovery.recover(build: widgetBuild)
      if recovered {
        languageDefaults.set(widgetBuild, forKey: WidgetUpgradeRecovery.completedBuildKey)
      }
      isRecoveringWidgetAfterUpgrade = false
      requestWidgetReload(reason: "app-build-changed")
    }
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
    guard !isRefreshing, let adapter = adapters[selectedSubscription] else { return }
    let requestedSubscription = selectedSubscription
    let revision = selectionRevision
    isRefreshing = true
    defer {
      isRefreshing = false
      applyPendingDisplayLanguageIfNeeded()
      if refreshRequested || revision != selectionRevision {
        refreshRequested = false
        Task { await refresh() }
      }
    }

    do {
      let reading = try await adapter.fetchUsage()
      guard revision == selectionRevision else { return }
      snapshot = reading.legacySnapshot
      subscriptionDetails = reading.details
      lastUpdated = reading.details.observedAt
      errorMessage = nil
      subscriptionError = nil
      if let pendingLanguage = takePendingDisplayLanguage() {
        updateDisplayLanguageState(pendingLanguage)
      }
      publishWidgetState()
    } catch {
      guard revision == selectionRevision else { return }
      let failure = (error as? SubscriptionUsageError) ?? .unavailable
      if requestedSubscription.connection == .existing {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      } else if failure.availability != .waiting {
        subscriptionError = failure
      } else {
        subscriptionError = nil
      }
      if failure.availability == .unavailable {
        subscriptionDetails = displayDetails.withAvailability(.unavailable)
      } else {
        snapshot = nil
        lastUpdated = nil
        subscriptionDetails = SubscriptionUsageDetails(
          subscription: requestedSubscription, availability: failure.availability)
      }
      publishWidgetState()
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

  private func restoreCachedSnapshot() {
    guard selectedSubscription.connection != .apiKey || hasSubscriptionKey else { return }
    let shared = sharedWidgetStateStore.load()
    let cached = appCacheStore.load()
    let current = WidgetSnapshotResolver.resolve(
      live: nil, shared: matchingSelection(shared), cached: matchingSelection(cached))
    let state = WidgetSnapshotResolver.resolve(
      live: nil, shared: current, cached: matchingSelection(subscriptionCacheStore.load()))
    if let state {
      snapshot = state.snapshot.map(UsageSnapshot.init(shared:))
      subscriptionDetails = state.displayDetails
      lastUpdated = state.displayDetails?.observedAt
      return
    }
    // A legacy raw file is only authoritative when no atomic publication exists.
    guard shared == nil, cached == nil, let legacy = sharedUsageStore.load(),
      let legacyState = matchingSelection(SharedWidgetState(snapshot: legacy, languageCode: nil))
    else { return }
    snapshot = legacyState.snapshot.map(UsageSnapshot.init(shared:))
    subscriptionDetails = legacyState.displayDetails
    lastUpdated = legacyState.displayDetails?.observedAt
  }

  private func matchingSelection(_ state: SharedWidgetState?) -> SharedWidgetState? {
    guard let state else { return nil }
    let owner =
      state.subscriptionID == nil ? .codex : UsageSubscription.recognized(state.subscriptionID)
    return owner == selectedSubscription ? state : nil
  }

  private var subscriptionCacheStore: SharedWidgetStateStore {
    SharedWidgetStateStore(
      directoryURL: SharedUsageConfiguration.appCacheDirectory
        .appendingPathComponent("subscriptions", isDirectory: true)
        .appendingPathComponent(selectedSubscription.rawValue, isDirectory: true))
  }

  func loadDocumentationPreview(
    subscription: UsageSubscription = .codex
  ) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current

    selectedSubscription = subscription
    clearReading()
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
    case .kimi:
      let monthlyReset = Date(timeIntervalSince1970: 1_791_024_000)
      let weeklyReset = monthlyReset.addingTimeInterval(-7 * 24 * 60 * 60)
      let shortReset = weeklyReset.addingTimeInterval(-24 * 60 * 60)
      snapshot = UsageSnapshot(
        usedPercent: 21, windowDurationMinutes: 0, resetsAt: monthlyReset,
        planType: "intermediate", limitName: "Kimi", reachedLimitType: nil,
        fiveHourWindow: UsageSubWindow(
          usedPercent: 50, windowDurationMinutes: 300, resetsAt: shortReset
        ),
        quotaWindows: [
          UsageQuotaWindow(kind: .monthly, usedPercent: 21, resetsAt: monthlyReset),
          UsageQuotaWindow(kind: .weekly, usedPercent: 35, resetsAt: weeklyReset),
          UsageQuotaWindow(kind: .fiveHour, usedPercent: 50, resetsAt: shortReset),
        ]
      )
    default:
      break
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
          try await Task.sleep(
            nanoseconds: UInt64(SharedUsageConfiguration.refreshInterval * 1_000_000_000)
          )
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
    languageDefaults.set(selectedSubscription.rawValue, forKey: UsageSubscription.storageKey)
    guard SharedUsageConfiguration.sharedStorageEnabled() else { return }
    do {
      try sharedWidgetPreferencesStore.save(
        SharedWidgetPreferences(
          languageCode: displayLanguage.rawValue,
          subscriptionID: selectedSubscription.rawValue
        )
      )
    } catch {
      WidgetSyncDiagnostics.failure("write-preferences", error: error)
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
    persistWidgetPreferences()
  }

  private func commitDisplayLanguage(_ language: AppLanguage) {
    updateDisplayLanguageState(language)
    publishWidgetState()
  }

  private func publishWidgetState() {
    let state = SharedWidgetState(
      snapshot: displaySnapshot, languageCode: displayLanguage.rawValue,
      subscriptionID: selectedSubscription.rawValue, publishedAt: Date(), details: displayDetails
    )
    localUsageServer.publish(state)
    do {
      try appCacheStore.save(state)
      try subscriptionCacheStore.save(state)
    } catch {
      WidgetSyncDiagnostics.failure("write-app-cache", error: error)
    }
    var shared = false
    do {
      if SharedUsageConfiguration.sharedStorageEnabled() {
        try sharedWidgetStateStore.save(state)
        shared = true
        // Keep on-disk compatibility while an older extension is still loaded.
        if let snapshot = state.snapshot {
          try sharedUsageStore.save(snapshot)
        } else {
          try sharedUsageStore.clear()
        }
      }
      widgetSyncFailed = false
    } catch {
      widgetSyncFailed = true
      WidgetSyncDiagnostics.failure("publish-shared-state", error: error)
    }
    WidgetSyncDiagnostics.published(state, shared: shared)
    let previous = lastPublishedWidgetState
    lastPublishedWidgetState = state
    if previous?.snapshot != state.snapshot || previous?.details != state.details
      || previous?.languageCode != state.languageCode
      || previous?.subscriptionID != state.subscriptionID
    {
      requestWidgetReload(reason: "state-changed")
    }
  }

  func requestWidgetReload(reason: String) {
    guard !isRecoveringWidgetAfterUpgrade else { return }
    WidgetSyncDiagnostics.reload(reason: reason)
    WidgetCenter.shared.reloadTimelines(
      ofKind: SharedUsageConfiguration.widgetKind
    )
  }

  func resumeAfterWake() async {
    await refreshIfStale()
    requestWidgetReload(reason: "wake")
  }
}
