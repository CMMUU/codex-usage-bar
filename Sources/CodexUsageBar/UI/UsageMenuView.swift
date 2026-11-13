import AppKit
import CodexUsageCore
import CodexUsageShared
import SwiftUI

struct UsageMenuView: View {
  @ObservedObject var viewModel: UsageViewModel
  @ObservedObject var updateManager: UpdateManager
  @Binding var language: AppLanguage
  @State private var subscriptionKey = ""
  @State private var copiedSetup = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      subscriptionPicker
      usageSection

      if let errorMessage = viewModel.errorDisplayText(for: language) {
        errorPanel(errorMessage)
      }
      connectionSection

      if viewModel.widgetSyncFailed {
        Text(language.widgetSyncFailureText)
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }

      Divider()
      detailsSection
      Divider()
      actionsSection
    }
    .padding(18)
    .frame(width: 340)
    .environment(\.locale, language.locale)
    .onChange(of: viewModel.selectedSubscription) { _ in
      subscriptionKey = ""
      copiedSetup = false
    }
    .task {
      await viewModel.refreshIfStale()
      updateManager.checkForUpdateInformationIfNeeded()
    }
  }

  private var header: some View {
    HStack {
      BrandMark()
        .frame(width: 32, height: 32)
      VStack(alignment: .leading, spacing: 3) {
        Text(viewModel.selectedSubscription.displayName(in: language))
          .font(.system(size: 18, weight: .bold, design: .rounded))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        Text(
          viewModel.selectedSubscription == .codex
            ? language.text(.subtitle) : language.text(.kimiSubtitle)
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer()

      HStack(spacing: 10) {
        if viewModel.isLanguageSwitching {
          HStack(spacing: 4) {
            ProgressView()
              .controlSize(.small)
            Text(language.text(.switchingLanguage))
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(language.text(.switchingLanguage))
        } else if viewModel.isRefreshing {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel(language.text(.refreshing))
        }

        LanguageSwitcher(
          language: $language,
          pendingLanguage: viewModel.pendingDisplayLanguage,
          isSwitching: viewModel.isLanguageSwitching,
          switchingText: language.text(.switchingLanguage)
        )
      }
    }
  }

  private var subscriptionPicker: some View {
    Menu {
      ForEach(UsageSubscription.allCases) { subscription in
        Button {
          viewModel.selectSubscription(subscription)
        } label: {
          HStack {
            Text(subscription.displayName(in: language))
            if subscription == viewModel.selectedSubscription {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      HStack(spacing: 6) {
        Text(viewModel.selectedSubscription.displayName(in: language))
          .font(.subheadline.weight(.semibold))
        Spacer()
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(
        .secondary.opacity(0.12),
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(language.text(.subscriptionPicker))
  }

  @ViewBuilder
  private var usageSection: some View {
    let details = viewModel.displayDetails
    if details.quotas.count > 3 {
      ScrollView {
        quotaList(details)
      }
      .frame(height: 256)
    } else if !details.quotas.isEmpty {
      quotaList(details)
    } else if viewModel.errorDisplayText(for: language) == nil {
      Text(language.quotaAvailabilityText(details.availability))
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private func quotaList(_ details: SubscriptionUsageDetails) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(details.quotas) { quota in
        quotaSection(quota, isPrimary: quota.id == details.primaryQuota?.id)
      }
    }
  }

  private func quotaSection(_ quota: SubscriptionQuota, isPrimary: Bool) -> some View {
    let title = quota.title(in: language, for: viewModel.selectedSubscription)
    let used = quota.usedText(in: language)
    return VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(isPrimary ? .headline : .subheadline.weight(.medium))
          .lineLimit(1)
        Spacer(minLength: 6)
        Text("\(language.widgetUsedText) \(used)")
          .font(.system(size: isPrimary ? 17 : 13, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.68)
      }
      if let percent = quota.usedPercent {
        UsageProgressBar(value: percent, color: progressColor(for: percent))
          .accessibilityHidden(true)
      }
      VStack(spacing: 4) {
        detailRow(language.text(.remainingQuota), value: quota.remainingText(in: language))
        detailRow(language.text(.resetTime), value: language.resetDisplayText(quota.resetsAt))
      }
      .font(.caption)
    }
    .accessibilityElement(children: .combine)
  }

  private var detailsSection: some View {
    let details = viewModel.displayDetails
    let now = Date()
    return VStack(alignment: .leading, spacing: 9) {
      detailRow(language.text(.currentPlan), value: details.planDisplayName(in: language))
      Text(details.observationText(in: language, relativeTo: now))
        .font(.caption)
        .foregroundStyle(details.isStale(relativeTo: now) ? .orange : .secondary)

      if let limitName = viewModel.snapshot?.limitName, !limitName.isEmpty {
        detailRow(language.text(.limitType), value: limitName)
      }
    }
    .font(.subheadline)
  }

  @ViewBuilder
  private var connectionSection: some View {
    switch viewModel.selectedSubscription.connection {
    case .apiKey:
      DisclosureGroup(language.text(.quotaManageConnection)) {
        VStack(alignment: .leading, spacing: 8) {
          SecureField(language.text(.quotaKey), text: $subscriptionKey)
            .textFieldStyle(.roundedBorder)
          HStack {
            Button(language.text(.quotaSaveConnection)) {
              if viewModel.connectWithKey(subscriptionKey) { subscriptionKey = "" }
            }
            .disabled(subscriptionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if viewModel.hasSubscriptionKey {
              Button(language.text(.quotaDisconnect)) {
                viewModel.disconnectKey()
                subscriptionKey = ""
              }
            }
          }
        }
        .padding(.top, 5)
      }
      .font(.caption)
    case .statusLine:
      statusLineSetup
    case .existing, .officialCLI:
      EmptyView()
    }
  }

  @ViewBuilder
  private var statusLineSetup: some View {
    let subscription = viewModel.selectedSubscription
    if let executable = Bundle.main.executableURL,
      let command = SubscriptionStatusLineCapture.command(for: subscription, executable: executable)
    {
      DisclosureGroup(language.text(.quotaManageConnection)) {
        VStack(alignment: .leading, spacing: 8) {
          Text(language.text(.quotaSetupHelp))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          HStack {
            Button(language.text(copiedSetup ? .quotaSetupCopied : .quotaCopySetup)) {
              NSPasteboard.general.clearContents()
              copiedSetup = NSPasteboard.general.setString(command, forType: .string)
            }
            let url =
              subscription == .claude
              ? URL(string: "https://code.claude.com/docs/en/statusline")!
              : URL(string: "https://antigravity.google/docs/cli/statusline")!
            Link(language.text(.quotaSetupGuide), destination: url)
          }
        }
        .padding(.top, 5)
      }
      .font(.caption)
    }
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

  private func progressColor(for usedPercent: Double) -> Color {
    if usedPercent >= 90 {
      return .red
    }
    if usedPercent >= 75 {
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

}

private struct LanguageSwitcher: View {
  @Binding var language: AppLanguage
  let pendingLanguage: AppLanguage?
  let isSwitching: Bool
  let switchingText: String

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
    let isPending = isSwitching && pendingLanguage == value

    return Button {
      language = value
    } label: {
      ZStack {
        Text(title)
          .font(.system(size: 10, weight: .semibold, design: .rounded))
          .opacity(isPending ? 0 : 1)

        if isPending {
          ProgressView()
            .controlSize(.mini)
            .accessibilityHidden(true)
        }
      }
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
    .disabled(isSwitching)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(isPending ? switchingText : "")
    .help(isPending ? switchingText : accessibilityLabel)
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
