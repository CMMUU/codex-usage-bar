import Foundation

/// One publication from the app. A nil snapshot explicitly clears the previous
/// subscription's quota; it must not be replaced by an older cached snapshot.
public struct SharedWidgetState: Codable, Equatable, Sendable {
  public let snapshot: SharedUsageSnapshot?
  public let languageCode: String?
  public let subscriptionID: String?
  public let publishedAt: Date?

  public init(
    snapshot: SharedUsageSnapshot?,
    languageCode: String?,
    subscriptionID: String? = nil,
    publishedAt: Date? = nil
  ) {
    let selected = subscriptionID ?? snapshot?.subscriptionID
    self.snapshot = snapshot.flatMap {
      selected == nil
        || UsageSubscription.resolve($0.subscriptionID)
          == UsageSubscription.resolve(selected)
        ? $0 : nil
    }
    self.languageCode = languageCode ?? snapshot?.languageCode
    self.subscriptionID = selected
    self.publishedAt = publishedAt
  }

  public var normalized: SharedWidgetState {
    SharedWidgetState(
      snapshot: snapshot, languageCode: languageCode,
      subscriptionID: subscriptionID, publishedAt: publishedAt
    )
  }

  /// Read old raw snapshots as well as the atomic state envelope.
  public static func decodeBridgeData(_ data: Data) -> SharedWidgetState? {
    let decoder = JSONDecoder()
    if let snapshot = try? decoder.decode(SharedUsageSnapshot.self, from: data) {
      return SharedWidgetState(snapshot: snapshot, languageCode: snapshot.languageCode)
    }
    guard let state = try? decoder.decode(Self.self, from: data),
      state.snapshot != nil || state.languageCode != nil
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
    let sharedDate = sharedState?.publishedAt ?? sharedState?.snapshot?.updatedAt ?? .distantPast
    let cachedDate = cachedState?.publishedAt ?? cachedState?.snapshot?.updatedAt ?? .distantPast
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
