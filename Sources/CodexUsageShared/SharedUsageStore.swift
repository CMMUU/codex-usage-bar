import Foundation

public enum SharedUsageStoreError: LocalizedError, Equatable {
  case appGroupUnavailable(String)

  public var errorDescription: String? {
    switch self {
    case .appGroupUnavailable(let identifier):
      return "无法访问 App Group：\(identifier)"
    }
  }
}

public struct SharedUsageStore {
  private static let fileName = "usage-snapshot.json"

  private let fileURL: URL?
  private let appGroupIdentifier: String?

  public init(
    appGroupIdentifier: String =
      SharedUsageConfiguration.appGroupIdentifier()
  ) {
    self.appGroupIdentifier = appGroupIdentifier
    fileURL = FileManager.default
      .containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      )?
      .appendingPathComponent(Self.fileName, isDirectory: false)
  }

  public init(directoryURL: URL) {
    appGroupIdentifier = nil
    fileURL = directoryURL.appendingPathComponent(
      Self.fileName,
      isDirectory: false
    )
  }

  public func load() -> SharedUsageSnapshot? {
    guard let fileURL else {
      return nil
    }
    guard let data = try? Data(contentsOf: fileURL) else {
      return nil
    }
    return try? JSONDecoder().decode(SharedUsageSnapshot.self, from: data)
  }

  public func save(_ snapshot: SharedUsageSnapshot) throws {
    guard let fileURL else {
      throw SharedUsageStoreError.appGroupUnavailable(
        appGroupIdentifier
          ?? SharedUsageConfiguration.fallbackAppGroupIdentifier
      )
    }

    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(snapshot)
    try data.write(to: fileURL, options: [.atomic])
  }
}

public struct SharedWidgetPreferences: Codable, Equatable, Sendable {
  public let languageCode: String
  public let subscriptionID: String?

  public init(languageCode: String, subscriptionID: String? = nil) {
    self.languageCode = languageCode
    self.subscriptionID = subscriptionID
  }
}

public struct SharedWidgetPreferencesStore {
  private static let fileName = "widget-preferences.json"

  private let fileURL: URL?
  private let appGroupIdentifier: String?

  public init(
    appGroupIdentifier: String =
      SharedUsageConfiguration.appGroupIdentifier()
  ) {
    self.appGroupIdentifier = appGroupIdentifier
    fileURL = FileManager.default
      .containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      )?
      .appendingPathComponent(Self.fileName, isDirectory: false)
  }

  public init(directoryURL: URL) {
    appGroupIdentifier = nil
    fileURL = directoryURL.appendingPathComponent(
      Self.fileName,
      isDirectory: false
    )
  }

  public func load() -> SharedWidgetPreferences? {
    guard
      let fileURL,
      let data = try? Data(contentsOf: fileURL)
    else {
      return nil
    }
    return try? JSONDecoder().decode(
      SharedWidgetPreferences.self,
      from: data
    )
  }

  public func save(_ preferences: SharedWidgetPreferences) throws {
    guard let fileURL else {
      throw SharedUsageStoreError.appGroupUnavailable(
        appGroupIdentifier
          ?? SharedUsageConfiguration.fallbackAppGroupIdentifier
      )
    }

    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(preferences)
    try data.write(to: fileURL, options: [.atomic])
  }
}
