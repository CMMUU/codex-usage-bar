import CodexUsageShared
import SwiftUI
import WidgetKit

private struct UsageTimelineEntry: TimelineEntry {
  let date: Date
  let snapshot: SharedUsageSnapshot?
}

private struct UsageTimelineProvider: TimelineProvider {
  private let store = SharedUsageStore()

  func placeholder(in context: Context) -> UsageTimelineEntry {
    UsageTimelineEntry(date: Date(), snapshot: .placeholder)
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (UsageTimelineEntry) -> Void
  ) {
    completion(
      UsageTimelineEntry(
        date: Date(),
        snapshot: context.isPreview ? .placeholder : store.load()
      )
    )
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<UsageTimelineEntry>) -> Void
  ) {
    let now = Date()
    let snapshot = store.load()
    let entry = UsageTimelineEntry(date: now, snapshot: snapshot)
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

private struct UsageWidgetView: View {
  @Environment(\.widgetFamily) private var family

  let entry: UsageTimelineEntry

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
          Text("剩余")
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
        metricRow("本周已用", percentText(snapshot.usedPercent))
        metricRow("剩余额度", percentText(snapshot.remainingPercent))
        metricRow("重置时间", resetDisplayText(snapshot.resetsAt))

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

      Text("等待用量数据")
        .font(.title3.weight(.semibold))
      Text("打开 Codex Usage Bar 完成首次刷新")
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
          .help("数据需要刷新")
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
        Text("已用")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 82, height: 82)
    .accessibilityLabel("本周已用")
    .accessibilityValue(percentText(snapshot.usedPercent))
  }

  private func resetText(
    _ snapshot: SharedUsageSnapshot
  ) -> some View {
    HStack(spacing: 5) {
      Image(systemName: "arrow.clockwise")
      Text("重置 \(resetDisplayText(snapshot.resetsAt))")
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

  private func resetDisplayText(_ date: Date?) -> String {
    guard let date else {
      return "未知"
    }
    return date.formatted(
      .dateTime
        .month(.defaultDigits)
        .day()
        .hour()
        .minute()
        .locale(Locale(identifier: "zh_CN"))
    )
  }

  private func updatedText(
    _ snapshot: SharedUsageSnapshot
  ) -> String {
    let time = snapshot.updatedAt.formatted(
      .dateTime
        .hour()
        .minute()
        .locale(Locale(identifier: "zh_CN"))
    )
    return snapshot.isStale() ? "上次更新 \(time) · 待刷新" : "更新于 \(time)"
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
    updatedAt: Date()
  )
}

struct CodexUsageWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: SharedUsageConfiguration.widgetKind,
      provider: UsageTimelineProvider()
    ) { entry in
      UsageWidgetView(entry: entry)
    }
    .configurationDisplayName("Codex 周限额")
    .description("快速查看本周已用比例、剩余额度与重置时间。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@main
struct CodexUsageWidgetBundle: WidgetBundle {
  var body: some Widget {
    CodexUsageWidget()
  }
}
