import CodexUsageShared
import SwiftUI

struct MenuBarLabel: View {
  @ObservedObject var viewModel: UsageViewModel
  let language: AppLanguage

  var body: some View {
    HStack(spacing: 4) {
      BrandMark(template: true)
        .frame(width: 16, height: 16)
      Text(viewModel.menuBarText)
        .monospacedDigit()
    }
    .accessibilityLabel(
      viewModel.selectedSubscription.displayName + " "
        + viewModel.primaryQuotaKind.title(in: language, for: viewModel.selectedSubscription)
    )
    .accessibilityValue(viewModel.menuBarText)
  }
}
