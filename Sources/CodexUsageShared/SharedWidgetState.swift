import Foundation

/// One publication from the app. A nil snapshot explicitly clears the previous
/// subscription's quota; it must not be replaced by an older cached snapshot.
public struct SharedWidgetState: Codable, Equatable, Sendable {
  public let snapshot: SharedUsageSnapshot?
  public let languageCode: String?
  public let subscriptionID: String?
  public let publishedAt: Date?
  public let details: SubscriptionUsageDetails?

  public init(
    snapshot: SharedUsageSnapshot?,
    languageCode: String?,
    subscriptionID: String? = nil,
    publishedAt: Date? = nil,
    details: SubscriptionUsageDetails? = nil
  ) {
    let selected = subscriptionID ?? details?.subscriptionID ?? snapshot?.subscriptionID
    let owner = selected == nil ? .codex : UsageSubscription.recognized(selected)
    self.snapshot = snapshot.flatMap { reading in
      let source =
        reading.subscriptionID == nil
        ? .codex
        : UsageSubscription.recognized(reading.subscriptionID)
      // The old percentage snapshot is only for the original two subscriptions.
      guard let source, source == owner, source.connection == .existing else { return nil }
      return reading
    }
    self.details = details?.normalized.flatMap {
      UsageSubscription.recognized($0.subscriptionID) == owner ? $0 : nil
    }
    self.languageCode = languageCode ?? snapshot?.languageCode
    self.subscriptionID = selected
    self.publishedAt = publishedAt
  }

  public var normalized: SharedWidgetState {
    SharedWidgetState(
      snapshot: snapshot, languageCode: languageCode,
      subscriptionID: subscriptionID, publishedAt: publishedAt, details: details
    )
  }

  public var displayDetails: SubscriptionUsageDetails? {
    if let details { return details }
    return snapshot.map {
      SubscriptionUsageDetails(legacy: $0, subscription: UsageSubscription.resolve(subscriptionID))
    }
  }

  /// Read old raw snapshots as well as the atomic state envelope.
  public static func decodeBridgeData(_ data: Data) -> SharedWidgetState? {
    let decoder = JSONDecoder()
    if let snapshot = try? decoder.decode(SharedUsageSnapshot.self, from: data) {
      return SharedWidgetState(snapshot: snapshot, languageCode: snapshot.languageCode)
    }
    guard let state = try? decoder.decode(Self.self, from: data),
      state.snapshot != nil || state.details != nil || state.languageCode != nil
        || state.subscriptionID != nil || state.publishedAt != nil
    else { return nil }
    return state.normalized
  }
}

public enum WidgetSnapshotResolver {
  public static func resolve(
    live: SharedWidgetState?,
    shared: SharedWidgetState?,
    cached: SharedWidgetState?
  ) -> SharedWidgetState? {
    select(live: live, shared: { shared }, cached: { cached }).state
  }

  /// Lazy fallbacks are essential: even reading an unauthorised container can
  /// invalidate a widget extension before it delivers its live timeline.
  public static func select(
    live: SharedWidgetState?,
    shared: () -> SharedWidgetState?,
    cached: () -> SharedWidgetState?
  ) -> WidgetStateSelection {
    if let live { return WidgetStateSelection(state: live.normalized, source: .live) }
    let sharedState = shared()
    let cachedState = cached()
    let sharedDate =
      sharedState?.publishedAt ?? sharedState?.displayDetails?.observedAt ?? .distantPast
    let cachedDate =
      cachedState?.publishedAt ?? cachedState?.displayDetails?.observedAt ?? .distantPast
    if let sharedState, cachedState == nil || sharedDate >= cachedDate {
      return WidgetStateSelection(state: sharedState.normalized, source: .shared)
    }
    return WidgetStateSelection(
      state: cachedState?.normalized, source: cachedState == nil ? .unavailable : .cached)
  }
}

public enum WidgetStateSource: String, Sendable {
  case live, shared, cached, unavailable
}

public struct WidgetStateSelection: Sendable {
  public let state: SharedWidgetState?
  public let source: WidgetStateSource
}

public struct SharedWidgetStateStore {
  private let fileURL: URL?
  private let appGroupIdentifier: String?

  public init(
    appGroupIdentifier: String = SharedUsageConfiguration.appGroupIdentifier(),
    enabled: Bool = SharedUsageConfiguration.sharedStorageEnabled()
  ) {
    self.appGroupIdentifier = appGroupIdentifier
    fileURL =
      enabled
      ? FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      )?.appendingPathComponent("widget-state.json") : nil
  }

  public init(directoryURL: URL) {
    appGroupIdentifier = nil
    fileURL = directoryURL.appendingPathComponent("widget-state.json")
  }

  public func load() -> SharedWidgetState? {
    do {
      return try loadIfPresent()
    } catch {
      WidgetSyncDiagnostics.failure("read-state", error: error)
      return nil
    }
  }

  public func loadIfPresent() throws -> SharedWidgetState? {
    guard let fileURL else { return nil }
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch CocoaError.fileReadNoSuchFile {
      return nil
    }
    return try JSONDecoder().decode(SharedWidgetState.self, from: data).normalized
  }

  public func save(_ state: SharedWidgetState) throws {
    guard let fileURL else {
      throw SharedUsageStoreError.appGroupUnavailable(
        appGroupIdentifier ?? SharedUsageConfiguration.fallbackAppGroupIdentifier
      )
    }
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try JSONEncoder().encode(state.normalized).write(to: fileURL, options: .atomic)
  }
}
