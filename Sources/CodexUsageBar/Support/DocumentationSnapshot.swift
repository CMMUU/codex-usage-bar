import AppKit
import CodexUsageShared
import SwiftUI

@MainActor
enum DocumentationSnapshot {
  static func render(
    viewModel: UsageViewModel,
    updateManager: UpdateManager,
    language: AppLanguage,
    to path: String
  ) throws {
    let content = UsageMenuView(
      viewModel: viewModel,
      updateManager: updateManager,
      language: .constant(language)
    )
    .fixedSize(horizontal: false, vertical: true)
    .background(Color(nsColor: .windowBackgroundColor))
    .environment(\.colorScheme, .light)

    // AppKit-backed buttons are not supported by ImageRenderer. Capture the
    // hosting view so the documentation includes the actual native controls.
    let hostingView = NSHostingView(rootView: content)
    hostingView.setFrameSize(hostingView.fittingSize)
    let window = NSWindow(
      contentRect: hostingView.bounds, styleMask: [.borderless],
      backing: .buffered, defer: false
    )
    window.contentView = hostingView
    hostingView.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
      throw DocumentationSnapshotError.renderFailed
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
      throw DocumentationSnapshotError.encodingFailed
    }

    let outputURL = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try pngData.write(to: outputURL, options: .atomic)
  }
}

private enum DocumentationSnapshotError: LocalizedError {
  case renderFailed
  case encodingFailed

  var errorDescription: String? {
    switch self {
    case .renderFailed:
      return "AppKit could not capture the documentation view"
    case .encodingFailed:
      return "AppKit could not encode the documentation image as PNG"
    }
  }
}
