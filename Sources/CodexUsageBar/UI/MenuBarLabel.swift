import SwiftUI

struct MenuBarLabel: View {
  @ObservedObject var viewModel: UsageViewModel

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "terminal")
      Text(viewModel.menuBarText)
        .monospacedDigit()
    }
    .accessibilityLabel("Codex 周限额")
    .accessibilityValue(viewModel.menuBarText)
  }
}
