import Foundation
import Network

public enum LocalUsageSnapshotBridgeConfiguration {
  public static let ports: [UInt16] = [51_872, 51_873, 51_874]
  public static let maximumPayloadSize = 64 * 1_024
  public static let maximumConcurrentConnections = 8
  public static let connectionTimeout: TimeInterval = 0.75
}

public final class LocalUsageSnapshotServer: @unchecked Sendable {
  private let ports: [NWEndpoint.Port]
  private let queue = DispatchQueue(
    label: "io.cmmuu.codex-usage-bar.snapshot-server"
  )
  private let snapshotLock = NSLock()

  private var snapshot: SharedUsageSnapshot?
  private var listener: NWListener?
  private var connections: [ObjectIdentifier: NWConnection] = [:]
  private var nextPortIndex = 0
  private var stopped = true

  public init(
    ports: [UInt16] = LocalUsageSnapshotBridgeConfiguration.ports
  ) {
    self.ports = ports.compactMap(NWEndpoint.Port.init(rawValue:))
  }

  public func start() {
    queue.async { [weak self] in
      guard let self, self.stopped else {
        return
      }
      self.stopped = false
      self.nextPortIndex = 0
      self.startNextListener()
    }
  }

  public func stop() {
    queue.async { [weak self] in
      guard let self else {
        return
      }
      self.stopped = true
      self.listener?.cancel()
      self.listener = nil
      for connection in self.connections.values {
        connection.cancel()
      }
      self.connections.removeAll()
    }
  }

  public func update(_ snapshot: SharedUsageSnapshot) {
    snapshotLock.lock()
    self.snapshot = snapshot
    snapshotLock.unlock()
  }

  private func startNextListener() {
    guard !stopped, nextPortIndex < ports.count else {
      return
    }

    let port = ports[nextPortIndex]
    nextPortIndex += 1

    let parameters = NWParameters.tcp
    parameters.requiredInterfaceType = .loopback
    parameters.allowLocalEndpointReuse = true

    do {
      let listener = try NWListener(using: parameters, on: port)
      self.listener = listener
      listener.stateUpdateHandler = { [weak self, weak listener] state in
        guard let self, self.listener === listener else {
          return
        }
        if case .failed = state {
          listener?.cancel()
          self.listener = nil
          self.startNextListener()
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        self?.accept(connection)
      }
      listener.start(queue: queue)
    } catch {
      startNextListener()
    }
  }

  private func accept(_ connection: NWConnection) {
    guard
      connections.count
        < LocalUsageSnapshotBridgeConfiguration.maximumConcurrentConnections
    else {
      connection.cancel()
      return
    }

    let identifier = ObjectIdentifier(connection)
    connections[identifier] = connection
    connection.stateUpdateHandler = { [weak self, weak connection] state in
      guard let self, let connection else {
        return
      }
      switch state {
      case .ready:
        self.sendSnapshot(over: connection, identifier: identifier)
      case .failed, .cancelled:
        self.finish(connection, identifier: identifier)
      default:
        break
      }
    }
    connection.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 2) { [weak self, weak connection] in
      guard
        let self,
        let connection,
        self.connections[identifier] != nil
      else {
        return
      }
      self.finish(connection, identifier: identifier)
    }
  }

  private func sendSnapshot(
    over connection: NWConnection,
    identifier: ObjectIdentifier
  ) {
    snapshotLock.lock()
    let snapshot = self.snapshot
    snapshotLock.unlock()

    guard
      let snapshot,
      let data = try? JSONEncoder().encode(snapshot),
      data.count <= LocalUsageSnapshotBridgeConfiguration.maximumPayloadSize
    else {
      finish(connection, identifier: identifier)
      return
    }

    connection.send(
      content: data,
      contentContext: .defaultMessage,
      isComplete: true,
      completion: .contentProcessed { [weak self, weak connection] _ in
        guard let self, let connection else {
          return
        }
        self.queue.async {
          self.finish(connection, identifier: identifier)
        }
      }
    )
  }

  private func finish(
    _ connection: NWConnection,
    identifier: ObjectIdentifier
  ) {
    connections.removeValue(forKey: identifier)
    connection.stateUpdateHandler = nil
    connection.cancel()
  }
}

public final class LocalUsageSnapshotClient: @unchecked Sendable {
  private let ports: [NWEndpoint.Port]
  private let timeout: TimeInterval
  private let queue = DispatchQueue(
    label: "io.cmmuu.codex-usage-bar.snapshot-client"
  )

  public init(
    ports: [UInt16] = LocalUsageSnapshotBridgeConfiguration.ports,
    timeout: TimeInterval =
      LocalUsageSnapshotBridgeConfiguration.connectionTimeout
  ) {
    self.ports = ports.compactMap(NWEndpoint.Port.init(rawValue:))
    self.timeout = max(0.1, timeout)
  }

  public func load(
    completion: @escaping (SharedUsageSnapshot?) -> Void
  ) {
    queue.async {
      self.attempt(portIndex: 0, completion: completion)
    }
  }

  private func attempt(
    portIndex: Int,
    completion: @escaping (SharedUsageSnapshot?) -> Void
  ) {
    guard portIndex < ports.count else {
      completion(nil)
      return
    }

    let parameters = NWParameters.tcp
    parameters.requiredInterfaceType = .loopback
    let connection = NWConnection(
      host: .ipv4(.loopback),
      port: ports[portIndex],
      using: parameters
    )
    var completed = false

    func finish(_ snapshot: SharedUsageSnapshot?) {
      guard !completed else {
        return
      }
      completed = true
      connection.stateUpdateHandler = nil
      connection.cancel()
      if let snapshot {
        completion(snapshot)
      } else {
        attempt(portIndex: portIndex + 1, completion: completion)
      }
    }

    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        connection.receive(
          minimumIncompleteLength: 1,
          maximumLength:
            LocalUsageSnapshotBridgeConfiguration.maximumPayloadSize
        ) { data, _, _, _ in
          let snapshot = data.flatMap {
            try? JSONDecoder().decode(
              SharedUsageSnapshot.self,
              from: $0
            )
          }
          finish(snapshot)
        }
      case .failed, .cancelled:
        finish(nil)
      default:
        break
      }
    }

    queue.asyncAfter(deadline: .now() + timeout) {
      finish(nil)
    }
    connection.start(queue: queue)
  }
}
