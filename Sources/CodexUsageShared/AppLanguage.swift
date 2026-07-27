import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
  case simplifiedChinese = "zh-Hans"
  case english = "en"

  public static let storageKey = "codex-usage-language"

  public static var systemDefault: AppLanguage {
    guard
      let preferredLanguage = Locale.preferredLanguages.first?.lowercased()
    else {
      return .english
    }
    return preferredLanguage.hasPrefix("zh") ? .simplifiedChinese : .english
  }

  public static func resolve(_ storedValue: String?) -> AppLanguage {
    guard let storedValue, let language = AppLanguage(rawValue: storedValue) else {
      return systemDefault
    }
    return language
  }

  public var id: String {
    rawValue
  }

  public var locale: Locale {
    Locale(identifier: rawValue)
  }

  public var toggled: AppLanguage {
    self == .simplifiedChinese ? .english : .simplifiedChinese
  }

  public func text(_ key: AppText) -> String {
    switch (self, key) {
    case (.simplifiedChinese, .subtitle):
      return "周限额使用情况"
    case (.english, .subtitle):
      return "Weekly limit usage"
    case (.simplifiedChinese, .refreshing):
      return "正在刷新"
    case (.english, .refreshing):
      return "Refreshing"
    case (.simplifiedChinese, .weeklyUsed):
      return "本周已用"
    case (.english, .weeklyUsed):
      return "Used this week"
    case (.simplifiedChinese, .remainingQuota):
      return "剩余额度"
    case (.english, .remainingQuota):
      return "Remaining"
    case (.simplifiedChinese, .resetTime):
      return "重置时间"
    case (.english, .resetTime):
      return "Reset time"
    case (.simplifiedChinese, .currentPlan):
      return "当前套餐"
    case (.english, .currentPlan):
      return "Current plan"
    case (.simplifiedChinese, .refreshTime):
      return "刷新时间"
    case (.english, .refreshTime):
      return "Updated"
    case (.simplifiedChinese, .limitType):
      return "限额类型"
    case (.english, .limitType):
      return "Limit type"
    case (.simplifiedChinese, .refreshNow):
      return "立即刷新"
    case (.english, .refreshNow):
      return "Refresh now"
    case (.simplifiedChinese, .quit):
      return "退出"
    case (.english, .quit):
      return "Quit"
    case (.simplifiedChinese, .launchAtLogin):
      return "登录时启动"
    case (.english, .launchAtLogin):
      return "Launch at login"
    case (.simplifiedChinese, .unknown):
      return "未知"
    case (.english, .unknown):
      return "Unknown"
    case (.simplifiedChinese, .notRefreshed):
      return "尚未刷新"
    case (.english, .notRefreshed):
      return "Not refreshed"
    case (.simplifiedChinese, .languagePicker):
      return "显示语言"
    case (.english, .languagePicker):
      return "Display language"
    case (.simplifiedChinese, .menuBarAccessibility):
      return "Codex 周限额"
    case (.english, .menuBarAccessibility):
      return "Codex weekly limit"
    case (.simplifiedChinese, .launchAtLoginUpdateFailed):
      return "更新登录启动设置失败"
    case (.english, .launchAtLoginUpdateFailed):
      return "Failed to update launch at login"
    }
  }

  public func resetDisplayText(_ date: Date?) -> String {
    guard let date else {
      return text(.unknown)
    }
    return format(
      date,
      dateFormat: self == .simplifiedChinese
        ? "M月d日 HH:mm"
        : "MMM d, HH:mm"
    )
  }

  public func lastUpdatedDisplayText(_ date: Date?) -> String {
    guard let date else {
      return text(.notRefreshed)
    }
    return format(date, dateFormat: "HH:mm:ss")
  }

  public func localizedErrorMessage(_ message: String) -> String {
    guard self == .english else {
      return message
    }

    let exactTranslations = [
      "读取 Codex 限额超时": "Timed out while reading the Codex limit",
      "Codex 当前未登录 ChatGPT": "Codex is not signed in to ChatGPT",
      "Codex app-server 返回了无法解析的数据":
        "Codex app-server returned data that could not be parsed",
      "Codex 没有返回限额数据": "Codex did not return limit data",
      "Codex 返回了限额数据，但没有找到周限额窗口":
        "Codex returned limit data, but no weekly window was found",
      "周限额数据缺少使用百分比":
        "The weekly limit data is missing its usage percentage",
      "未找到 Codex CLI。请安装 Codex，或通过 CODEX_BINARY_PATH 指定可执行文件。":
        "Codex CLI was not found. Install Codex or set CODEX_BINARY_PATH.",
    ]
    if let translated = exactTranslations[message] {
      return translated
    }

    let prefixTranslations = [
      "启动 Codex app-server 失败：": "Failed to start Codex app-server: ",
      "Codex app-server 已退出，状态码：":
        "Codex app-server exited with status: ",
      "Codex app-server 未返回 ": "Codex app-server did not return ",
      "Codex app-server 的 ": "Codex app-server response for ",
      "Codex app-server 错误 ": "Codex app-server error ",
    ]
    for (prefix, translatedPrefix) in prefixTranslations
    where message.hasPrefix(prefix) {
      var suffix = String(message.dropFirst(prefix.count))
      if prefix == "Codex app-server 的 ",
        suffix.hasSuffix(" 响应缺少结果")
      {
        suffix.removeLast(" 响应缺少结果".count)
        return "\(translatedPrefix)\(suffix) is missing a result"
      }
      return translatedPrefix + suffix.replacingOccurrences(of: "：", with: ": ")
    }

    return message
  }

  private func format(_ date: Date, dateFormat: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateFormat = dateFormat
    return formatter.string(from: date)
  }
}

public enum AppText: Sendable {
  case subtitle
  case refreshing
  case weeklyUsed
  case remainingQuota
  case resetTime
  case currentPlan
  case refreshTime
  case limitType
  case refreshNow
  case quit
  case launchAtLogin
  case unknown
  case notRefreshed
  case languagePicker
  case menuBarAccessibility
  case launchAtLoginUpdateFailed
}
