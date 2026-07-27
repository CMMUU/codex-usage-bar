import CodexUsageShared
import SwiftUI

@main
struct CodexUsageBarApp: App {
  @StateObject private var viewModel = UsageViewModel()
  @AppStorage(AppLanguage.storageKey)
  private var storedLanguage = AppLanguage.systemDefault.rawValue
  private let documentationSnapshotPath =
    ProcessInfo.processInfo.environment["CODEX_USAGE_BAR_DOCUMENTATION_SNAPSHOT"]
  private let documentationSnapshotLanguage =
    ProcessInfo.processInfo.environment["CODEX_USAGE_BAR_DOCUMENTATION_LANGUAGE"]

  var body: some Scene {
    MenuBarExtra {
      UsageMenuView(
        viewModel: viewModel,
        language: languageBinding
      )
    } label: {
      MenuBarLabel(
        viewModel: viewModel,
        language: language
      )
      .task {
        if let documentationSnapshotPath {
          viewModel.loadDocumentationPreview()
          do {
            try DocumentationSnapshot.render(
              viewModel: viewModel,
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
