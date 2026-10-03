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
    // The running app is authoritative, including a subscription with no data.
    if let live { return live.normalized }
    let candidates = [shared, cached].compactMap { $0 }
    return candidates.max {
      ($0.publishedAt ?? $0.snapshot?.updatedAt ?? .distantPast)
        < ($1.publishedAt ?? $1.snapshot?.updatedAt ?? .distantPast)
    }?.normalized
  }
}

public struct SharedWidgetStateStore {
  private let fileURL: URL?
  private let appGroupIdentifier: String?

  public init(
    appGroupIdentifier: String = SharedUsageConfiguration.appGroupIdentifier()
  ) {
    self.appGroupIdentifier = appGroupIdentifier
    fileURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    )?.appendingPathComponent("widget-state.json")
  }

  public init(directoryURL: URL) {
    appGroupIdentifier = nil
    fileURL = directoryURL.appendingPathComponent("widget-state.json")
  }

  public func load() -> SharedWidgetState? {
    guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
    return (try? JSONDecoder().decode(SharedWidgetState.self, from: data))?.normalized
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
