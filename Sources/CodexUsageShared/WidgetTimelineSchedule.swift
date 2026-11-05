import Foundation

public enum WidgetTimelineSchedule {
  /// Pre-render a stale state even if a later system reload is delayed or fails.
  public static func entryDates(updatedAt: Date?, now: Date) -> [Date] {
    guard let updatedAt else { return [now] }
    let staleAt = updatedAt.addingTimeInterval(SharedUsageConfiguration.staleInterval + 1)
    return staleAt > now ? [now, staleAt] : [now]
  }
}
