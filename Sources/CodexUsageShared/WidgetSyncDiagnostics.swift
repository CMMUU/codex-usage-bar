import Foundation
import OSLog

public enum WidgetSyncDiagnostics {
  private static let logger = Logger(subsystem: "io.cmmuu.codex-usage-bar", category: "widget-sync")

  public static func received(_ selection: WidgetStateSelection) {
    let source = selection.source.rawValue
    let updatedAt = selection.state?.snapshot?.updatedAt.timeIntervalSince1970 ?? 0
    logger.info(
      "Widget state source=\(source, privacy: .public) updatedAt=\(updatedAt, privacy: .public)")
  }

  public static func published(_ state: SharedWidgetState, shared: Bool) {
    let updatedAt = state.snapshot?.updatedAt.timeIntervalSince1970 ?? 0
    logger.info(
      "Published widget state shared=\(shared, privacy: .public) updatedAt=\(updatedAt, privacy: .public)"
    )
  }

  public static func reload(reason: String) {
    logger.info("Requested widget reload reason=\(reason, privacy: .public)")
  }

  public static func failure(_ operation: String, error: Error) {
    let error = error as NSError
    // Do not log credentials, quota values, or local filesystem paths.
    logger.error(
      "Widget sync failure operation=\(operation, privacy: .public) domain=\(error.domain, privacy: .public) code=\(error.code, privacy: .public)"
    )
  }
}
