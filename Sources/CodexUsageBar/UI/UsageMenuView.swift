import AppKit
import CodexUsageShared
import SwiftUI

struct UsageMenuView: View {
  @ObservedObject var viewModel: UsageViewModel
  @ObservedObject var updateManager: UpdateManager
  @Binding var language: AppLanguage

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      usageSection

      if let errorMessage = viewModel.errorDisplayText(for: language) {
        errorPanel(errorMessage)
      }

      Divider()
      detailsSection
      Divider()
      actionsSection
    }
    .padding(18)
    .frame(width: 340)
    .environment(\.locale, language.locale)
    .task {
      await viewModel.refreshIfStale()
      updateManager.checkForUpdateInformationIfNeeded()
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text("CODEX")
          .font(.system(size: 18, weight: .bold, design: .rounded))
        Text(language.text(.subtitle))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      HStack(spacing: 10) {
        if viewModel.isRefreshing {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel(language.text(.refreshing))
        }

        LanguageSwitcher(language: $language)
      }
    }
  }

  private var usageSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(language.text(.weeklyUsed))
          .font(.headline)
        Spacer()
        Text(percentText(viewModel.snapshot?.usedPercent))
          .font(.system(size: 26, weight: .semibold, design: .rounded))
          .monospacedDigit()
      }

      UsageProgressBar(
        value: viewModel.snapshot?.usedPercent ?? 0,
        color: progressColor
      )
      .accessibilityLabel(language.text(.weeklyUsed))
      .accessibilityValue(percentText(viewModel.snapshot?.usedPercent))

      HStack {
        Text(language.text(.remainingQuota))
          .foregroundStyle(.secondary)
        Spacer()
        Text(percentText(viewModel.snapshot?.remainingPercent))
          .fontWeight(.medium)
          .monospacedDigit()
      }
      .font(.subheadline)
    }
  }

  private var detailsSection: some View {
    VStack(spacing: 9) {
      detailRow(
        language.text(.resetTime),
        value: viewModel.resetDisplayText(for: language)
      )
      detailRow(
        language.text(.currentPlan),
        value: viewModel.planDisplayName(for: language)
      )
      detailRow(
        language.text(.refreshTime),
        value: viewModel.lastUpdatedDisplayText(for: language)
      )

      if let limitName = viewModel.snapshot?.limitName, !limitName.isEmpty {
        detailRow(language.text(.limitType), value: limitName)
      }
    }
    .font(.subheadline)
  }

  private var actionsSection: some View {
    VStack(spacing: 10) {
      HStack {
        Button {
          Task {
            await viewModel.refresh()
          }
        } label: {
          Label(language.text(.refreshNow), systemImage: "arrow.clockwise")
        }
        .disabled(viewModel.isRefreshing)

        Spacer()

        Button(language.text(.quit)) {
          NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
      }

      HStack(spacing: 8) {
        Button {
          updateManager.checkForUpdates()
        } label: {
          Label(
            updateButtonTitle,
            systemImage: updateButtonSystemImage
          )
        }
        .disabled(
          !updateManager.canCheckForUpdates
            || updateManager.status == .checking
        )

        Spacer()

        updateStatusBadge
      }

      Toggle(
        language.text(.launchAtLogin),
        isOn: Binding(
          get: { viewModel.launchAtLoginEnabled },
          set: { viewModel.setLaunchAtLogin($0) }
        )
      )
      .toggleStyle(CompactSwitchToggleStyle())

      if let launchAtLoginError =
        viewModel.launchAtLoginErrorText(for: language)
      {
        Text(launchAtLoginError)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var updateButtonTitle: String {
    switch updateManager.status {
    case .checking:
      return language.text(.checkingForUpdates)
    case .available:
      return language.text(.updateNow)
    default:
      return language.text(.checkForUpdates)
    }
  }

  private var updateButtonSystemImage: String {
    switch updateManager.status {
    case .available:
      return "arrow.down.circle"
    default:
      return "arrow.triangle.2.circlepath"
    }
  }

  @ViewBuilder
  private var updateStatusBadge: some View {
    switch updateManager.status {
    case .idle, .checking:
      EmptyView()
    case .upToDate:
      Text(language.text(.upToDate))
        .foregroundStyle(.secondary)
        .font(.caption)
    case .available(let version):
      HStack(spacing: 4) {
        Circle()
          .fill(Color.accentColor)
          .frame(width: 6, height: 6)
        Text(
          "\(language.text(.updateAvailable)) \(displayVersion(version))"
        )
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .foregroundStyle(Color.accentColor)
      .background(
        Color.accentColor.opacity(0.12),
        in: Capsule()
      )
      .font(.caption)
    case .failed(let message):
      Label(
        language.text(.updateCheckFailed),
        systemImage: "exclamationmark.circle"
      )
      .foregroundStyle(.orange)
      .font(.caption)
      .help(message)
    }
  }

  private func displayVersion(_ version: String) -> String {
    version.hasPrefix("v") ? version : "v\(version)"
  }

  private var progressColor: Color {
    guard let used = viewModel.snapshot?.usedPercent else {
      return .accentColor
    }
    if used >= 90 {
      return .red
    }
    if used >= 75 {
      return .orange
    }
    return .accentColor
  }

  private func detailRow(_ title: String, value: String) -> some View {
    HStack {
      Text(title)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
    }
  }

  private func errorPanel(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(message)
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(10)
    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
  }

  private func percentText(_ value: Double?) -> String {
    guard let value else {
      return "--"
    }
    return "\(Int(value.rounded()))%"
  }
}

private struct LanguageSwitcher: View {
  @Binding var language: AppLanguage

  var body: some View {
    HStack(spacing: 2) {
      languageButton(
        title: "中",
        value: .simplifiedChinese,
        accessibilityLabel: "中文"
      )
      languageButton(
        title: "EN",
        value: .english,
        accessibilityLabel: "English"
      )
    }
    .padding(2)
    .background(
      .secondary.opacity(0.12),
      in: RoundedRectangle(cornerRadius: 7, style: .continuous)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(language.text(.languagePicker))
  }

  private func languageButton(
    title: String,
    value: AppLanguage,
    accessibilityLabel: String
  ) -> some View {
    Button {
      language = value
    } label: {
      Text(title)
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(language == value ? .primary : .secondary)
        .frame(width: 32, height: 20)
        .background(
          language == value
            ? Color(nsColor: .controlBackgroundColor)
            : .clear,
          in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .shadow(
          color: language == value ? .black.opacity(0.12) : .clear,
          radius: 1,
          y: 1
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }
}

private struct UsageProgressBar: View {
  let value: Double
  let color: Color

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(.secondary.opacity(0.18))

        Capsule()
          .fill(color)
          .frame(
            width: geometry.size.width * min(1, max(0, value / 100))
          )
      }
    }
    .frame(height: 8)
  }
}

private struct CompactSwitchToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack {
        configuration.label
        Spacer()
        Capsule()
          .fill(configuration.isOn ? Color.accentColor : .secondary.opacity(0.25))
          .frame(width: 34, height: 20)
          .overlay(alignment: configuration.isOn ? .trailing : .leading) {
            Circle()
              .fill(.white)
              .padding(2)
              .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
          }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
