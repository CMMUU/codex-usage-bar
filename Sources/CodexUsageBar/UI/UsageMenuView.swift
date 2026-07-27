import AppKit
import SwiftUI

struct UsageMenuView: View {
  @ObservedObject var viewModel: UsageViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      usageSection

      if let errorMessage = viewModel.errorMessage {
        errorPanel(errorMessage)
      }

      Divider()
      detailsSection
      Divider()
      actionsSection
    }
    .padding(18)
    .frame(width: 340)
    .task {
      await viewModel.refreshIfStale()
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text("CODEX")
          .font(.system(size: 18, weight: .bold, design: .rounded))
        Text("周限额使用情况")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if viewModel.isRefreshing {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel("正在刷新")
      }
    }
  }

  private var usageSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("本周已用")
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
      .accessibilityLabel("本周已用")
      .accessibilityValue(percentText(viewModel.snapshot?.usedPercent))

      HStack {
        Text("剩余额度")
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
      detailRow("重置时间", value: viewModel.resetDisplayText)
      detailRow("当前套餐", value: viewModel.planDisplayName)
      detailRow("刷新时间", value: viewModel.lastUpdatedDisplayText)

      if let limitName = viewModel.snapshot?.limitName, !limitName.isEmpty {
        detailRow("限额类型", value: limitName)
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
          Label("立即刷新", systemImage: "arrow.clockwise")
        }
        .disabled(viewModel.isRefreshing)

        Spacer()

        Button("退出") {
          NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
      }

      Toggle(
        "登录时启动",
        isOn: Binding(
          get: { viewModel.launchAtLoginEnabled },
          set: { viewModel.setLaunchAtLogin($0) }
        )
      )
      .toggleStyle(CompactSwitchToggleStyle())

      if let launchAtLoginError = viewModel.launchAtLoginError {
        Text(launchAtLoginError)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
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
