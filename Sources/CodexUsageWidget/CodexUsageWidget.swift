import CodexUsageShared
import SwiftUI
import WidgetKit

private struct UsageTimelineEntry: TimelineEntry {
  let date: Date
  let state: SharedWidgetState?
}

private struct UsageTimelineProvider: TimelineProvider {
  private let appGroupStateStore = SharedWidgetStateStore()
  private let widgetStateCacheStore = SharedWidgetStateStore(
    directoryURL: Self.widgetCacheDirectory)
  private let appGroupStore = SharedUsageStore()
  private let widgetCacheStore = SharedUsageStore(directoryURL: Self.widgetCacheDirectory)
  private let appGroupPreferencesStore = SharedWidgetPreferencesStore()
  private let widgetPreferencesCacheStore = SharedWidgetPreferencesStore(
    directoryURL: Self.widgetCacheDirectory)
  private let localClient = LocalUsageSnapshotClient()

  func placeholder(in context: Context) -> UsageTimelineEntry {
    let snapshot = SharedUsageSnapshot.placeholder
    return UsageTimelineEntry(
      date: Date(),
      state: SharedWidgetState(snapshot: snapshot, languageCode: snapshot.languageCode))
  }

  func getSnapshot(in context: Context, completion: @escaping (UsageTimelineEntry) -> Void) {
    if context.isPreview {
      completion(placeholder(in: context))
      return
    }
    loadState { state in
      completion(UsageTimelineEntry(date: Date(), state: state))
    }
  }

  func getTimeline(
    in context: Context, completion: @escaping (Timeline<UsageTimelineEntry>) -> Void
  ) {
    loadState { state in
      let now = Date()
      let details = state?.displayDetails
      let nextReset = details?.quotas.compactMap(\.resetsAt).filter { $0 > now }.min()
      var dates = WidgetTimelineSchedule.entryDates(updatedAt: details?.observedAt, now: now)
      if let nextReset, let last = dates.last, nextReset < last {
        dates.insert(nextReset, at: 1)
      }
      let entries = dates.map { UsageTimelineEntry(date: $0, state: state) }
      let routineRefresh = now.addingTimeInterval(SharedUsageConfiguration.refreshInterval)
      let refreshDate =
        nextReset.map { min(routineRefresh, max(now.addingTimeInterval(60), $0)) }
        ?? routineRefresh

      completion(Timeline(entries: entries, policy: .after(refreshDate)))
    }
  }

  private func loadState(completion: @escaping (SharedWidgetState?) -> Void) {
    // Consult the live app first because App Group storage can lag behind it.
    localClient.loadPayload { live in
      let selection = WidgetSnapshotResolver.select(
        live: live,
        shared: {
          appGroupStateStore.load()
            ?? legacyState(
              snapshot: appGroupStore.load(), preferences: appGroupPreferencesStore.load())
        },
        cached: {
          widgetStateCacheStore.load()
            ?? legacyState(
              snapshot: widgetCacheStore.load(), preferences: widgetPreferencesCacheStore.load())
        })
      if let state = selection.state {
        do { try widgetStateCacheStore.save(state) } catch {
          WidgetSyncDiagnostics.failure("write-widget-cache", error: error)
        }
      }
      WidgetSyncDiagnostics.received(selection)
      completion(selection.state)
    }
  }

  private func legacyState(
    snapshot: SharedUsageSnapshot?, preferences: SharedWidgetPreferences?
  ) -> SharedWidgetState? {
    guard snapshot != nil || preferences != nil else { return nil }
    return SharedWidgetState(
      snapshot: snapshot, languageCode: preferences?.languageCode,
      subscriptionID: preferences?.subscriptionID)
  }

  private static let widgetCacheDirectory = SharedUsageConfiguration.widgetCacheDirectory
}

private struct UsageWidgetView: View {
  @Environment(\.widgetFamily) private var family

  let entry: UsageTimelineEntry

  private var language: AppLanguage {
    AppLanguage.resolve(entry.state?.languageCode)
  }

  private var subscription: UsageSubscription {
    UsageSubscription.resolve(entry.state?.subscriptionID)
  }

  var body: some View {
    Group {
      if let details = entry.state?.displayDetails, let primary = details.primaryQuota {
        if family == .systemMedium {
          mediumContent(details)
        } else {
          smallContent(details, quota: primary)
        }
      } else {
        emptyContent(entry.state?.displayDetails?.availability ?? .waiting)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .modifier(WidgetBackgroundModifier())
    .environment(\.locale, language.locale)
    .accessibilityElement(children: .combine)
  }

  private func smallContent(
    _ details: SubscriptionUsageDetails, quota: SubscriptionQuota
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      header(stale: details.isStale(relativeTo: entry.date))
      planLine(details)
      Spacer(minLength: 0)
      Text(quota.title(in: language, for: subscription))
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      amountLine(language.widgetUsedText, value: quota.usedText(in: language))
      amountLine(language.text(.remainingQuota), value: quota.remainingText(in: language))
      Spacer(minLength: 0)
      resetLine(quota)
      observationLine(details)
    }
    .padding(10)
  }

  private func mediumContent(_ details: SubscriptionUsageDetails) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 5) {
        header(stale: details.isStale(relativeTo: entry.date))
        planLine(details)
        Spacer(minLength: 0)
        observationLine(details)
      }
      .frame(width: 99, alignment: .leading)

      Divider()

      VStack(alignment: .leading, spacing: 5) {
        ForEach(details.quotas.prefix(3)) { quota in
          VStack(alignment: .leading, spacing: 1) {
            Text(quota.title(in: language, for: subscription))
              .font(.caption.weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
              amountLine(language.widgetUsedText, value: quota.usedText(in: language))
              amountLine(language.text(.remainingQuota), value: quota.remainingText(in: language))
            }
            resetLine(quota)
          }
        }
        if details.quotas.count > 3 {
          Text(language.text(.quotaSeeMore))
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
  }

  private func emptyContent(_ availability: SubscriptionUsageAvailability) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      header(stale: false)
      Spacer(minLength: 0)
      Text(language.quotaAvailabilityText(availability))
        .font(.subheadline.weight(.semibold))
      Text(language.widgetWaitingBody)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
  }

  private func header(stale: Bool) -> some View {
    HStack(spacing: 4) {
      BrandMark().frame(width: 15, height: 15)
      Text(subscription.displayName(in: language))
        .font(.caption.weight(.bold))
        .lineLimit(1)
        .minimumScaleFactor(0.64)
      Spacer(minLength: 0)
      if stale {
        Image(systemName: "clock.badge.exclamationmark")
          .font(.caption2)
          .foregroundStyle(.orange)
          .accessibilityLabel(language.widgetStaleHelp)
      }
    }
  }

  private func planLine(_ details: SubscriptionUsageDetails) -> some View {
    Text(details.planDisplayName(in: language))
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .minimumScaleFactor(0.72)
      .accessibilityLabel(language.text(.currentPlan))
      .accessibilityValue(details.planDisplayName(in: language))
  }

  private func amountLine(_ title: String, value: String) -> some View {
    HStack(spacing: 3) {
      Text(title).foregroundStyle(.secondary)
      Text(value).fontWeight(.semibold).monospacedDigit()
    }
    .font(.caption2)
    .lineLimit(1)
    .minimumScaleFactor(0.7)
  }

  private func resetLine(_ quota: SubscriptionQuota) -> some View {
    Text(language.widgetResetText(quota.resetsAt))
      .font(.system(size: 9))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
  }

  private func observationLine(_ details: SubscriptionUsageDetails) -> some View {
    Text(details.observationText(in: language, relativeTo: entry.date))
      .font(.system(size: 9))
      .foregroundStyle(details.isStale(relativeTo: entry.date) ? .orange : .secondary)
      .lineLimit(1)
      .minimumScaleFactor(0.72)
  }
}

private struct WidgetBackgroundModifier: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 14.0, *) {
      content.containerBackground(for: .widget) {
        LinearGradient(
          colors: [
            Color.accentColor.opacity(0.12),
            Color.primary.opacity(0.035),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
    } else {
      content.background(
        LinearGradient(
          colors: [
            Color.accentColor.opacity(0.12),
            Color.primary.opacity(0.035),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
    }
  }
}

extension SharedUsageSnapshot {
  fileprivate static let placeholder = SharedUsageSnapshot(
    usedPercent: 64,
    resetsAt: Date().addingTimeInterval(3 * 24 * 60 * 60),
    planType: "pro",
    limitName: "Codex",
    updatedAt: Date(),
    languageCode: AppLanguage.systemDefault.rawValue
  )
}

struct CodexUsageWidget: Widget {
  // Configuration metadata must not read a container before the live provider
  // runs. The actual widget language comes from its atomic timeline entry.
  private let language = AppLanguage.systemDefault

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: SharedUsageConfiguration.widgetKind,
      provider: UsageTimelineProvider()
    ) { entry in
      UsageWidgetView(entry: entry)
    }
    .configurationDisplayName(language.widgetDisplayName)
    .description(language.text(.quotaWidgetDescription))
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@main
struct CodexUsageWidgetBundle: WidgetBundle {
  var body: some Widget {
    CodexUsageWidget()
  }
}
