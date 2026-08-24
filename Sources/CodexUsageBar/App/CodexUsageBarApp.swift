import CodexUsageShared
import SwiftUI

@main
struct CodexUsageBarApp: App {
  @StateObject private var viewModel = UsageViewModel()
  @StateObject private var updateManager: UpdateManager
  private let documentationSnapshotPath =
    ProcessInfo.processInfo.environment["CODEX_USAGE_BAR_DOCUMENTATION_SNAPSHOT"]
  private let documentationSnapshotLanguage =
    ProcessInfo.processInfo.environment["CODEX_USAGE_BAR_DOCUMENTATION_LANGUAGE"]
  private let documentationSnapshotSubscription =
    ProcessInfo.processInfo.environment[
      "CODEX_USAGE_BAR_DOCUMENTATION_SUBSCRIPTION"
    ]

  init() {
    let isDocumentationSnapshot =
      ProcessInfo.processInfo.environment[
        "CODEX_USAGE_BAR_DOCUMENTATION_SNAPSHOT"
      ] != nil
    _updateManager = StateObject(
      wrappedValue: UpdateManager(
        startingUpdater: !isDocumentationSnapshot,
        previewStatus: isDocumentationSnapshot
          ? .available(version: "0.3.3")
          : nil
      )
    )
  }

  var body: some Scene {
    MenuBarExtra {
      UsageMenuView(
        viewModel: viewModel,
        updateManager: updateManager,
        language: languageBinding
      )
    } label: {
      MenuBarLabel(
        viewModel: viewModel,
        language: language
      )
      .task {
        if let documentationSnapshotPath {
          viewModel.loadDocumentationPreview(
            subscription: UsageSubscription.resolve(
              documentationSnapshotSubscription
            )
          )
          do {
            try DocumentationSnapshot.render(
              viewModel: viewModel,
              updateManager: updateManager,
              language: documentationLanguage,
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

  private var language: AppLanguage {
    viewModel.displayLanguage
  }

  private var languageBinding: Binding<AppLanguage> {
    Binding(
      get: { viewModel.displayLanguage },
      set: { viewModel.setDisplayLanguage($0) }
    )
  }

  private var documentationLanguage: AppLanguage {
    guard
      let documentationSnapshotLanguage,
      let language = AppLanguage(rawValue: documentationSnapshotLanguage)
    else {
      return language
    }
    return language
  }
}
