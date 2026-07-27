import SwiftUI

@main
struct CodexUsageBarApp: App {
  @StateObject private var viewModel = UsageViewModel()
  private let documentationSnapshotPath =
    ProcessInfo.processInfo.environment["CODEX_USAGE_BAR_DOCUMENTATION_SNAPSHOT"]

  var body: some Scene {
    MenuBarExtra {
      UsageMenuView(viewModel: viewModel)
    } label: {
      MenuBarLabel(viewModel: viewModel)
        .task {
          if let documentationSnapshotPath {
            viewModel.loadDocumentationPreview()
            do {
              try DocumentationSnapshot.render(
                viewModel: viewModel,
                to: documentationSnapshotPath
              )
            } catch {
              fputs("Documentation snapshot failed: \(error)\n", stderr)
            }
            NSApplication.shared.terminate(nil)
          } else {
            await viewModel.activate()
          }
        }
    }
    .menuBarExtraStyle(.window)
  }
}
