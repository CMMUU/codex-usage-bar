import CryptoKit
import Darwin
import Foundation
import LightweightCodeRequirements
import OSLog
import Security

enum WidgetUpgradeRecovery {
  static let completedBuildKey = "widgetRecoveryCompletedBuild"

  private static let appID = "io.cmmuu.codex-usage-bar"
  private static let widgetID = appID + ".widget"
  private static let logger = Logger(subsystem: appID, category: "widget-sync")

  static func pendingBuild(defaults: UserDefaults, bundle: Bundle = .main) -> String? {
    guard bundle.bundleIdentifier == appID,
      let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      !version.isEmpty, !build.isEmpty
    else { return nil }
    let identity = "\(version) (\(build))"
    return defaults.string(forKey: completedBuildKey) == identity ? nil : identity
  }

  static func recover(build: String, bundle: Bundle = .main) async -> Bool {
    guard #available(macOS 15, *),
      bundle.object(forInfoDictionaryKey: "CodexUsageSharedStorageEnabled") as? Bool == true
    else { return true }

    do {
      let result = try await restartOutdatedWidgets(bundle: bundle)
      logger.info(
        "Widget upgrade recovery build=\(build, privacy: .public) restarted=\(result.restarted, privacy: .public) pending=\(result.pending, privacy: .public)"
      )
      return result.pending == 0
    } catch {
      let failure = error as NSError
      logger.error(
        "Widget upgrade recovery failed build=\(build, privacy: .public) domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)"
      )
      return false
    }
  }

  @available(macOS 15, *)
  private static func restartOutdatedWidgets(bundle: Bundle) async throws -> (
    restarted: Int, pending: Int
  ) {
    guard bundle.bundleIdentifier == appID,
      let extensionURL = bundle.builtInPlugInsURL?
        .appendingPathComponent("CodexUsageWidget.appex", isDirectory: true),
      let widget = Bundle(url: extensionURL), widget.bundleIdentifier == widgetID,
      let executable = widget.executableURL,
      let group = bundle.object(forInfoDictionaryKey: "CodexUsageAppGroupIdentifier") as? String,
      let team = group.split(separator: ".").first.map(String.init),
      group == "\(team).\(appID)",
      let appTask = SecTaskCreateFromSelf(nil)
    else { throw RecoveryError.unverifiedInstallation }

    let appIdentity = try ProcessCodeRequirement.allOf {
      SigningIdentifier(appID)
      TeamIdentifier(team)
      ValidationCategory(.developerID)
      ProcessCodeSigningFlags.isSuperset(of: [.isDynamicallyValid])
    }
    let installedIdentity = try OnDiskCodeRequirement.allOf {
      SigningIdentifier(widgetID)
      TeamIdentifier(team)
      ValidationCategory(.developerID)
    }
    var staticCode: SecStaticCode?
    guard try SecTaskValidateForRequirement(task: appTask, requirement: appIdentity),
      SecStaticCodeCreateWithPath(extensionURL as CFURL, [], &staticCode) == errSecSuccess,
      let staticCode
    else { throw RecoveryError.unverifiedInstallation }
    let validation = SecStaticCodeCheckValidityWithOnDiskRequirement(
      code: staticCode, flags: [], requirement: installedIdentity)
    guard validation.signatureIsValid && validation.requirementMatched else {
      throw RecoveryError.unverifiedInstallation
    }

    let plistURL = extensionURL.appendingPathComponent("Contents/Info.plist")
    let plistHash = Data(SHA256.hash(data: try Data(contentsOf: plistURL)))
    let currentBuild = try ProcessCodeRequirement.allOf { InfoPlistHash(plistHash) }
    let widgetIdentity = try ProcessCodeRequirement.allOf {
      SigningIdentifier(widgetID)
      TeamIdentifier(team)
      ValidationCategory(.developerID)
      ProcessCodeSigningFlags.isSuperset(of: [.isDynamicallyValid])
    }

    var signaled: [pid_t] = []
    var failed = 0
    for pid in try userProcesses() {
      guard var token = auditToken(for: pid, named: executable.lastPathComponent),
        let task = SecTaskCreateWithAuditToken(nil, token),
        (try? SecTaskValidateForRequirement(task: task, requirement: widgetIdentity)) == true,
        (try? SecTaskValidateForRequirement(task: task, requirement: currentBuild)) == false
      else { continue }

      // The audit token binds the signal to the same process generation we checked.
      let status = proc_signal_with_audittoken(&token, SIGTERM)
      if status == 0 {
        signaled.append(pid)
      } else if status != ESRCH {
        failed += 1
      }
    }

    let signalCount = signaled.count
    let deadline = ContinuousClock.now + .seconds(2)
    while !signaled.isEmpty {
      signaled.removeAll { kill($0, 0) != 0 && errno == ESRCH }
      guard !signaled.isEmpty, ContinuousClock.now < deadline else { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    return (restarted: signalCount - signaled.count, pending: failed + signaled.count)
  }

  private static func userProcesses() throws -> [pid_t] {
    let bytes = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
    guard bytes > 0 else { throw RecoveryError.processListUnavailable }
    var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 64)
    let count = pids.withUnsafeMutableBytes { buffer in
      proc_listpids(UInt32(PROC_UID_ONLY), getuid(), buffer.baseAddress, Int32(buffer.count))
    }
    guard count > 0, Int(count) < pids.count * MemoryLayout<pid_t>.size else {
      throw RecoveryError.processListUnavailable
    }
    return Array(pids.prefix(Int(count) / MemoryLayout<pid_t>.size))
  }

  private static func auditToken(for pid: pid_t, named executable: String) -> audit_token_t? {
    guard pid > 0 else { return nil }
    var process = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &process, size) == size,
      process.pbi_uid == getuid()
    else { return nil }
    let name = withUnsafeBytes(of: &process.pbi_name) {
      String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    }
    guard name == executable else { return nil }

    var taskName = mach_port_name_t()
    guard task_name_for_pid(mach_task_self_, pid, &taskName) == KERN_SUCCESS else { return nil }
    defer { mach_port_deallocate(mach_task_self_, taskName) }
    var token = audit_token_t()
    let capacity = MemoryLayout<audit_token_t>.size / MemoryLayout<integer_t>.size
    var count = mach_msg_type_number_t(capacity)
    let status = withUnsafeMutablePointer(to: &token) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
        task_info(taskName, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
      }
    }
    guard status == KERN_SUCCESS, count == capacity else { return nil }
    return token
  }

  private enum RecoveryError: Error {
    case unverifiedInstallation
    case processListUnavailable
  }
}
