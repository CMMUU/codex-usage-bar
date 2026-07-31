import CodexUsageShared
import SwiftUI

@main
struct CodexUsageBarApp: App {
  @StateObject private var viewModel = UsageViewModel()
  @StateObject private var updateManager: UpdateManager
  @AppStorage(AppLanguage.storageKey)
  private var storedLanguage = AppLanguage.systemDefault.rawValue
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
          ? .available(version: "0.2.2")
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
          viewModel.setDisplayLanguage(language)
          await viewModel.activate()
        }
      }
    }
    .menuBarExtraStyle(.window)
  }

  private var language: AppLanguage {
    AppLanguage.resolve(storedLanguage)
  }

  private var languageBinding: Binding<AppLanguage> {
    Binding(
      get: { AppLanguage.resolve(storedLanguage) },
      set: {
        storedLanguage = $0.rawValue
        viewModel.setDisplayLanguage($0)
      }
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
