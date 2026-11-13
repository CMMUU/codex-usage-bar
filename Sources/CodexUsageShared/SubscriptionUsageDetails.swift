import Foundation

public enum SubscriptionQuotaUnit: String, Codable, Sendable {
  case percent, requests, tokens, credits, unspecified
}

public enum SubscriptionUsageAvailability: String, Codable, Sendable {
  case available, waiting, notConnected, unavailable
}

/// A provider's quota bucket. Missing observations must stay missing.
public struct SubscriptionQuota: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let kind: UsageQuotaKind
  public let label: String?
  public let unit: SubscriptionQuotaUnit
  public let used: Double?
  public let remaining: Double?
  public let limit: Double?
  public let resetsAt: Date?
  public let isUnlimited: Bool

  public init(
    id: String, kind: UsageQuotaKind = .unknown, label: String? = nil,
    unit: SubscriptionQuotaUnit, used: Double? = nil, remaining: Double? = nil,
    limit: Double? = nil, resetsAt: Date? = nil, isUnlimited: Bool = false
  ) {
    self.id = String(id.prefix(96))
    self.kind = kind
    self.label = Self.cleanLabel(label)
    self.unit = unit
    self.used = Self.valid(used, unit: unit)
    self.remaining = isUnlimited ? nil : Self.valid(remaining, unit: unit)
    self.limit = isUnlimited ? nil : Self.valid(limit, unit: unit)
    self.resetsAt = resetsAt
    self.isUnlimited = isUnlimited
  }

  private static func valid(_ number: Double?, unit: SubscriptionQuotaUnit) -> Double? {
    guard let number, number.isFinite, number >= 0, unit != .percent || number <= 100 else {
      return nil
    }
    return number
  }

  static func cleanLabel(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.components(separatedBy: .controlCharacters).joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : String(trimmed.prefix(64))
  }

  public var normalized: Self {
    Self(
      id: id, kind: kind, label: label, unit: unit, used: used, remaining: remaining,
      limit: limit, resetsAt: resetsAt, isUnlimited: isUnlimited)
  }

  public var usedAmount: Double? {
    if let used { return used }
    guard !isUnlimited, let remaining, let cap = unit == .percent ? 100 : limit,
      cap > 0, remaining <= cap
    else { return nil }
    return cap - remaining
  }

  public var remainingAmount: Double? {
    guard !isUnlimited else { return nil }
    if let remaining { return remaining }
    guard let used, let cap = unit == .percent ? 100 : limit, cap > 0 else { return nil }
    return max(0, cap - used)
  }

  public var usedPercent: Double? {
    guard !isUnlimited, let usedAmount else { return nil }
    if unit == .percent { return usedAmount }
    guard let limit, limit > 0 else { return nil }
    return min(100, usedAmount / limit * 100)
  }

  public var hasReading: Bool {
    used != nil || remaining != nil || limit != nil || isUnlimited
  }

  public func title(in language: AppLanguage, for subscription: UsageSubscription) -> String {
    if let label { return label }
    if subscription == .volcengineArk && id == "session" { return language.text(.quotaSession) }
    return kind.title(in: language, for: subscription)
  }

  public func usedText(in language: AppLanguage) -> String {
    format(usedAmount, in: language)
  }

  public func remainingText(in language: AppLanguage) -> String {
    isUnlimited ? language.text(.unlimitedQuota) : format(remainingAmount, in: language)
  }

  public func menuBarValue(in language: AppLanguage) -> String? {
    if unit == .percent, usedAmount != nil { return usedText(in: language) }
    if isUnlimited { return language.text(.unlimitedQuota) }
    // Label an amount as used or remaining; do not imply it is a percentage.
    if usedAmount != nil { return "\(language.widgetUsedText) \(usedText(in: language))" }
    if remainingAmount != nil {
      return "\(language.text(.remainingQuota)) \(remainingText(in: language))"
    }
    return nil
  }

  private func format(_ value: Double?, in language: AppLanguage) -> String {
    guard let value else { return "—" }
    if unit == .percent { return "\(Int(value.rounded()))%" }
    let formatter = NumberFormatter()
    formatter.locale = language.locale
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 2
    let number = formatter.string(from: NSNumber(value: value)) ?? "—"
    let unitName = language.quotaUnitText(unit)
    return unitName.isEmpty ? number : "\(number) \(unitName)"
  }
}

/// Only normalized display data crosses the app/widget boundary.
public struct SubscriptionUsageDetails: Codable, Equatable, Sendable {
  public let subscriptionID: String
  public let planName: String?
  public let quotas: [SubscriptionQuota]
  public let observedAt: Date?
  public let availability: SubscriptionUsageAvailability

  public init(
    subscription: UsageSubscription, planName: String? = nil, quotas: [SubscriptionQuota] = [],
    observedAt: Date? = nil, availability: SubscriptionUsageAvailability = .available
  ) {
    subscriptionID = subscription.rawValue
    self.planName = SubscriptionQuota.cleanLabel(planName)
    self.quotas = Self.normalizedQuotas(quotas)
    self.observedAt = self.quotas.isEmpty ? nil : observedAt
    self.availability = self.quotas.isEmpty && availability == .available ? .waiting : availability
  }

  private static func normalizedQuotas(_ quotas: [SubscriptionQuota]) -> [SubscriptionQuota] {
    var seen = Set<String>()
    var result: [SubscriptionQuota] = []
    for quota in quotas {
      let quota = quota.normalized
      guard quota.hasReading, !quota.id.isEmpty, seen.insert(quota.id).inserted else { continue }
      result.append(quota)
      if result.count == 16 { break }
    }
    return result
  }

  public var primaryQuota: SubscriptionQuota? { quotas.first }

  public var normalized: Self? {
    guard let subscription = UsageSubscription.recognized(subscriptionID) else { return nil }
    return Self(
      subscription: subscription, planName: planName, quotas: quotas, observedAt: observedAt,
      availability: availability)
  }

  public init(legacy snapshot: SharedUsageSnapshot, subscription: UsageSubscription) {
    let quotas = snapshot.displayQuotas.map {
      SubscriptionQuota(
        id: $0.kind.rawValue, kind: $0.kind, unit: .percent,
        used: $0.usedPercent, resetsAt: $0.resetsAt)
    }
    self.init(
      subscription: subscription, planName: snapshot.planType, quotas: quotas,
      observedAt: snapshot.updatedAt)
  }

  public func withAvailability(_ availability: SubscriptionUsageAvailability) -> Self {
    guard let subscription = UsageSubscription.recognized(subscriptionID) else { return self }
    return Self(
      subscription: subscription, planName: planName, quotas: quotas, observedAt: observedAt,
      availability: availability)
  }

  public func isStale(relativeTo date: Date = Date()) -> Bool {
    guard let observedAt else { return false }
    return availability == .unavailable
      || quotas.contains { $0.resetsAt.map { $0 <= date } ?? false }
      || date.timeIntervalSince(observedAt) > SharedUsageConfiguration.staleInterval
  }

  public func observationText(in language: AppLanguage, relativeTo now: Date = Date()) -> String {
    guard let observedAt else { return language.text(.notRefreshed) }
    return language.widgetUpdatedText(
      observedAt, isStale: isStale(relativeTo: now), relativeTo: now)
  }

  public func planDisplayName(in language: AppLanguage) -> String {
    guard let planName else { return language.text(.quotaNotProvided) }
    return planName.prefix(1).uppercased() + planName.dropFirst()
  }
}
