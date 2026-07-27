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
    .background(Color(nsColor: .windowBackgroundColor))
    .environment(\.colorScheme, .light)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(width: 340, height: 475)

    guard let image = renderer.cgImage else {
      throw DocumentationSnapshotError.renderFailed
    }

    let bitmap = NSBitmapImageRep(cgImage: image)
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
      return "SwiftUI ImageRenderer did not produce an image"
    case .encodingFailed:
      return "AppKit could not encode the documentation image as PNG"
    }
  }
}
