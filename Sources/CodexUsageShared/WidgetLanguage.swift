import Foundation

extension AppLanguage {
  public var widgetUsedText: String {
    self == .simplifiedChinese ? "已用" : "Used"
  }

  public var widgetWaitingTitle: String {
    self == .simplifiedChinese ? "等待用量数据" : "Waiting for usage data"
  }

  public var widgetWaitingBody: String {
    self == .simplifiedChinese
      ? "打开 Codex Usage Bar 完成首次刷新"
      : "Open Codex Usage Bar to complete the first refresh"
  }

  public var widgetStaleHelp: String {
    self == .simplifiedChinese ? "数据需要刷新" : "Usage data needs a refresh"
  }

  public var widgetDisplayName: String {
    self == .simplifiedChinese ? "Codex 周限额" : "Codex Weekly Limit"
  }

  public var widgetDescription: String {
    self == .simplifiedChinese
      ? "快速查看本周已用比例、剩余额度与重置时间。"
      : "Quickly check weekly usage, remaining quota, and reset time."
  }

  public func widgetResetText(_ date: Date?) -> String {
    let value = resetDisplayText(date)
    return self == .simplifiedChinese ? "重置 \(value)" : "Reset \(value)"
  }

  public func widgetUpdatedText(
    _ date: Date,
    isStale: Bool
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateFormat = "HH:mm"
    let time = formatter.string(from: date)

    if self == .simplifiedChinese {
      return isStale ? "上次更新 \(time) · 待刷新" : "更新于 \(time)"
    }
    return isStale ? "Last updated \(time) · Refresh needed" : "Updated \(time)"
  }
}
