import Combine
import Foundation
import Sparkle

enum UpdateStatus: Equatable {
  case idle
  case checking
  case upToDate
  case available(version: String)
  case failed(message: String)
}

@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
  @Published private(set) var status: UpdateStatus = .idle
  @Published private(set) var canCheckForUpdates = false

  private var updaterController: SPUStandardUpdaterController!
  private var canCheckCancellable: AnyCancellable?
  private var lastProbeDate: Date?
  private var shouldProbeWhenReady = false
  private let isEnabled: Bool

  init(
    startingUpdater: Bool = true,
    previewStatus: UpdateStatus? = nil
  ) {
    isEnabled = startingUpdater
    super.init()

    updaterController = SPUStandardUpdaterController(
      startingUpdater: startingUpdater,
      updaterDelegate: self,
      userDriverDelegate: nil
    )

    if let previewStatus {
      status = previewStatus
      canCheckForUpdates = true
    }

    guard startingUpdater else {
      return
    }

    let updater = updaterController.updater
    canCheckForUpdates = updater.canCheckForUpdates
    canCheckCancellable = updater.publisher(for: \.canCheckForUpdates)
      .sink { [weak self] canCheck in
        Task { @MainActor in
          self?.canCheckForUpdates = canCheck
          if canCheck, self?.shouldProbeWhenReady == true {
            self?.checkForUpdateInformationIfNeeded()
          }
        }
      }
  }

  func checkForUpdateInformationIfNeeded(
    minimumInterval: TimeInterval = 3_600
  ) {
    guard isEnabled else {
      return
    }
    guard canCheckForUpdates else {
      shouldProbeWhenReady = true
      return
    }
    shouldProbeWhenReady = false
    if let lastProbeDate,
      Date().timeIntervalSince(lastProbeDate) < minimumInterval
    {
      return
    }

    lastProbeDate = Date()
    status = .checking
    updaterController.updater.checkForUpdateInformation()
  }

  func checkForUpdates() {
    guard isEnabled, canCheckForUpdates else {
      return
    }
    status = .checking
    updaterController.updater.checkForUpdates()
  }

  func updater(
    _ updater: SPUUpdater,
    didFindValidUpdate item: SUAppcastItem
  ) {
    status = .available(version: item.displayVersionString)
  }

  func updaterDidNotFindUpdate(
    _ updater: SPUUpdater,
    error: any Error
  ) {
    status = .upToDate
  }

  func updater(
    _ updater: SPUUpdater,
    didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
    error: (any Error)?
  ) {
    guard let error, status == .checking else {
      return
    }
    status = .failed(message: error.localizedDescription)
  }
}
