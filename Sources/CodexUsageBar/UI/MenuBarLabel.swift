import CodexUsageShared
import SwiftUI

struct MenuBarLabel: View {
  @ObservedObject var viewModel: UsageViewModel
  let language: AppLanguage

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "terminal")
      Text(viewModel.menuBarText)
        .monospacedDigit()
    }
    .accessibilityLabel(
      language.text(
        viewModel.selectedSubscription.usesWeeklyWindow
          ? .menuBarAccessibility : .k3MenuBarAccessibility
      )
    )
    .accessibilityValue(viewModel.menuBarText)
  }
}
