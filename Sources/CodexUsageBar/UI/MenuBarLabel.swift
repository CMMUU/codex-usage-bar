import CodexUsageShared
import SwiftUI

struct MenuBarLabel: View {
  @ObservedObject var viewModel: UsageViewModel
  let language: AppLanguage

  var body: some View {
    Text(viewModel.menuBarText)
      .monospacedDigit()
      .accessibilityLabel(
        viewModel.selectedSubscription.displayName + " "
          + viewModel.primaryQuotaKind.title(in: language, for: viewModel.selectedSubscription)
      )
      .accessibilityValue(viewModel.menuBarText)
  }
}
