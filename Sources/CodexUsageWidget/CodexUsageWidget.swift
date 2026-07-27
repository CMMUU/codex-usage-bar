import CodexUsageShared
import SwiftUI
import WidgetKit

private struct UsageTimelineEntry: TimelineEntry {
  let date: Date
  let snapshot: SharedUsageSnapshot?
  let languageCode: String?

  init(
    date: Date,
    snapshot: SharedUsageSnapshot?,
    languageCode: String? = nil
  ) {
    self.date = date
    self.snapshot = snapshot
    self.languageCode = languageCode
  }
}

private struct UsageTimelineProvider: TimelineProvider {
  private let appGroupStore = SharedUsageStore()
  private let widgetCacheStore = SharedUsageStore(
    directoryURL: Self.widgetCacheDirectory
  )
  private let appGroupPreferencesStore = SharedWidgetPreferencesStore()
  private let widgetPreferencesCacheStore = SharedWidgetPreferencesStore(
    directoryURL: Self.widgetCacheDirectory
  )
  private let localClient = LocalUsageSnapshotClient()

  func placeholder(in context: Context) -> UsageTimelineEntry {
    UsageTimelineEntry(date: Date(), snapshot: .placeholder)
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (UsageTimelineEntry) -> Void
  ) {
    if context.isPreview {
      completion(UsageTimelineEntry(date: Date(), snapshot: .placeholder))
      return
    }
    loadSnapshot { snapshot, languageCode in
      completion(
        UsageTimelineEntry(
          date: Date(),
          snapshot: snapshot,
          languageCode: languageCode
        )
      )
    }
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<UsageTimelineEntry>) -> Void
  ) {
    loadSnapshot { snapshot, languageCode in
      let now = Date()
      let entry = UsageTimelineEntry(
        date: now,
        snapshot: snapshot,
        languageCode: languageCode
      )
      let routineRefresh = now.addingTimeInterval(15 * 60)
      let refreshDate =
        snapshot?.resetsAt.map {
          min(routineRefresh, max(now.addingTimeInterval(60), $0))
        } ?? routineRefresh

      completion(
        Timeline(entries: [entry], policy: .after(refreshDate))
      )
    }
  }

  private func loadSnapshot(
    completion: @escaping (SharedUsageSnapshot?, String?) -> Void
  ) {
    let sharedLanguageCode =
      appGroupPreferencesStore.load()?.languageCode

    if let snapshot = appGroupStore.load() {
      completion(
        snapshot,
        sharedLanguageCode ?? snapshot.languageCode
      )
      return
    }

    localClient.loadPayload { payload in
      let snapshot = payload?.snapshot ?? widgetCacheStore.load()
      let languageCode =
        payload?.languageCode
        ?? sharedLanguageCode
        ?? widgetPreferencesCacheStore.load()?.languageCode
        ?? snapshot?.languageCode

      if let networkSnapshot = payload?.snapshot {
        try? widgetCacheStore.save(networkSnapshot)
      }
      if let languageCode {
        try? widgetPreferencesCacheStore.save(
          SharedWidgetPreferences(languageCode: languageCode)
        )
      }

      completion(snapshot, languageCode)
    }
  }

  private static let widgetCacheDirectory =
    FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    .appendingPathComponent(
      "CodexUsageWidget",
      isDirectory: true
    )
}

private struct UsageWidgetView: View {
  @Environment(\.widgetFamily) private var family

  let entry: UsageTimelineEntry

  private var language: AppLanguage {
    AppLanguage.resolve(
      entry.languageCode ?? entry.snapshot?.languageCode
    )
  }

  var body: some View {
    Group {
      if let snapshot = entry.snapshot {
        switch family {
        case .systemMedium:
          mediumContent(snapshot)
        default:
          smallContent(snapshot)
        }
      } else {
        emptyContent
      }
    }
    .modifier(WidgetBackgroundModifier())
    .environment(\.locale, language.locale)
    .accessibilityElement(children: .combine)
  }

  private func smallContent(
    _ snapshot: SharedUsageSnapshot
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      header(snapshot)

      Spacer(minLength: 0)

      HStack(alignment: .center, spacing: 12) {
        usageRing(snapshot)

        VStack(alignment: .leading, spacing: 4) {
          Text(language.text(.remainingQuota))
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(percentText(snapshot.remainingPercent))
            .font(.title3.weight(.semibold))
            .monospacedDigit()
        }
      }

      Spacer(minLength: 0)

      resetText(snapshot)
    }
    .padding(14)
  }

  private func mediumContent(
    _ snapshot: SharedUsageSnapshot
  ) -> some View {
    HStack(spacing: 18) {
      VStack(alignment: .leading, spacing: 10) {
        header(snapshot)
        usageRing(snapshot)
      }

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        metricRow(
          language.text(.weeklyUsed),
          percentText(snapshot.usedPercent)
        )
        metricRow(
          language.text(.remainingQuota),
          percentText(snapshot.remainingPercent)
        )
        metricRow(
          language.text(.resetTime),
          language.resetDisplayText(snapshot.resetsAt)
        )

        Spacer(minLength: 0)

        Text(updatedText(snapshot))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16)
  }

  private var emptyContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("CODEX", systemImage: "chart.bar.fill")
        .font(.headline)

      Spacer()

      Text(language.widgetWaitingTitle)
        .font(.title3.weight(.semibold))
      Text(language.widgetWaitingBody)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
  }

  private func header(
    _ snapshot: SharedUsageSnapshot
  ) -> some View {
    HStack(spacing: 6) {
      Text("CODEX")
        .font(.headline)
      Spacer(minLength: 4)
      if snapshot.isStale() {
        Image(systemName: "clock.badge.exclamationmark")
          .foregroundStyle(.orange)
          .help(language.widgetStaleHelp)
      } else {
        Circle()
          .fill(progressColor(snapshot.usedPercent))
          .frame(width: 7, height: 7)
          .accessibilityHidden(true)
      }
    }
  }

  private func usageRing(
    _ snapshot: SharedUsageSnapshot
  ) -> some View {
    ZStack {
      Circle()
        .stroke(.secondary.opacity(0.16), lineWidth: 8)
      Circle()
        .trim(from: 0, to: snapshot.usedPercent / 100)
        .stroke(
          progressColor(snapshot.usedPercent),
          style: StrokeStyle(lineWidth: 8, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
      VStack(spacing: 0) {
        Text(percentText(snapshot.usedPercent))
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .monospacedDigit()
        Text(language.widgetUsedText)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 82, height: 82)
    .accessibilityLabel(language.text(.weeklyUsed))
    .accessibilityValue(percentText(snapshot.usedPercent))
  }

  private func resetText(
    _ snapshot: SharedUsageSnapshot
  ) -> some View {
    HStack(spacing: 5) {
      Image(systemName: "arrow.clockwise")
      Text(language.widgetResetText(snapshot.resetsAt))
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
  }

  private func metricRow(
    _ title: String,
    _ value: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
    }
  }

  private func progressColor(_ usedPercent: Double) -> Color {
    if usedPercent >= 90 {
      return .red
    }
    if usedPercent >= 75 {
      return .orange
    }
    return .accentColor
  }

  private func percentText(_ value: Double) -> String {
    "\(Int(value.rounded()))%"
  }

  private func updatedText(
    _ snapshot: SharedUsageSnapshot
  ) -> String {
    language.widgetUpdatedText(
      snapshot.updatedAt,
      isStale: snapshot.isStale()
    )
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
  private let language = AppLanguage.resolve(
    SharedWidgetPreferencesStore().load()?.languageCode
  )

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: SharedUsageConfiguration.widgetKind,
      provider: UsageTimelineProvider()
    ) { entry in
      UsageWidgetView(entry: entry)
    }
    .configurationDisplayName(language.widgetDisplayName)
    .description(language.widgetDescription)
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@main
struct CodexUsageWidgetBundle: WidgetBundle {
  var body: some Widget {
    CodexUsageWidget()
  }
}
