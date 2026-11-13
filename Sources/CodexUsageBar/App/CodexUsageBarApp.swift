import AppKit
import CodexUsageCore
import CodexUsageShared
import SwiftUI

@main
@MainActor
enum CodexUsageBarEntry {
  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == SubscriptionStatusLineCapture.argument {
      captureStatusLine(provider: arguments.dropFirst().first)
      return
    }
    CodexUsageBarApp.main()
  }

  private static func captureStatusLine(provider: String?) {
    guard let subscription = UsageSubscription.recognized(provider),
      subscription.connection == .statusLine
    else { return }
    do {
      var input = Data()
      let maximum = SubscriptionStatusLineCapture.maximumBytes
      while let data = try FileHandle.standardInput.read(upToCount: 8192), !data.isEmpty {
        guard input.count + data.count <= maximum else { return }
        input.append(data)
      }
      guard try SubscriptionStatusLineCapture.ingest(input, for: subscription) != nil else {
        return
      }
      DistributedNotificationCenter.default().postNotificationName(
        SubscriptionStatusLineCapture.notificationName, object: subscription.rawValue,
        userInfo: nil, deliverImmediately: true)
    } catch {
      fputs("Codex Usage Bar could not capture the subscription quota.\n", stderr)
    }
  }
}

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
          ? .available(version: "0.4.6")
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
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
      ) { _ in
        viewModel.requestWidgetReload(reason: "background")
      }
      .onReceive(
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
      ) { _ in
        Task { await viewModel.resumeAfterWake() }
      }
      .onReceive(
        DistributedNotificationCenter.default().publisher(
          for: SubscriptionStatusLineCapture.notificationName
        ).receive(on: RunLoop.main)
      ) { notification in
        viewModel.statusLineDidChange(provider: notification.object as? String)
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
