import AppKit
import SwiftUI

/// The same approved mark is bundled by both the app and its widget extension.
public struct BrandMark: View {
  private let template: Bool

  public init(template: Bool = false) {
    self.template = template
  }

  public var body: some View {
    Image(nsImage: Self.image)
      .resizable()
      .renderingMode(template ? .template : .original)
      .interpolation(.high)
      .scaledToFit()
      .accessibilityHidden(true)
  }

  private static let image: NSImage = {
    guard let url = resourceBundle.url(forResource: "BrandMark", withExtension: "png"),
      let image = NSImage(contentsOf: url)
    else {
      preconditionFailure("Missing bundled BrandMark.png")
    }
    return image
  }()

  private static var resourceBundle: Bundle {
    #if SWIFT_PACKAGE
      .module
    #else
      .main
    #endif
  }
}
