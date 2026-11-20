import Foundation
import Observation
import os

/// App icons fetched from a remote machine's daemon with `GetAppIcon`, kept in memory per
/// machine and bundle path. "No icon" is kept too, so it is asked for once. Never asks twice
/// for the same icon at once. A failed request is logged and not kept; it is asked again once
/// `retryAfter` has passed, so a list redrawing every snapshot does not hammer the daemon.
///
/// Observable: a list that asked for an icon redraws when it arrives.
@MainActor
@Observable
public final class RemoteIconCache {
    public enum Entry: Sendable, Equatable {
        case png(Data)
        /// The daemon has no icon for the bundle; show the placeholder.
        case noIcon
    }

    public struct Key: Hashable, Sendable {
        public var machineID: String
        public var bundlePath: String

        public init(machineID: String, bundlePath: String) {
            self.machineID = machineID
            self.bundlePath = bundlePath
        }
    }

    /// How long a failed icon is not asked for again.
    public static let retryAfter: Duration = .seconds(30)

    public private(set) var entries: [Key: Entry] = [:]
    /// Requests sent so far. For tests and logging.
    @ObservationIgnored public private(set) var requestCount = 0

    @ObservationIgnored private var inFlight: [Key: Task<Void, Never>] = [:]
    /// When each failed icon may be asked for again.
    @ObservationIgnored private var failedUntil: [Key: ContinuousClock.Instant] = [:]
    @ObservationIgnored private let now: @Sendable () -> ContinuousClock.Instant
    @ObservationIgnored private let makeClient: MonitorClientFactory
    @ObservationIgnored private let logger = Logger(subsystem: "app.computa.Computa", category: "icons")

    /// - Parameter now: The clock for the retry delay. Tests pass one they control.
    public init(
        makeClient: @escaping MonitorClientFactory = { DaemonClient(endpoint: $0) },
        now: (@Sendable () -> ContinuousClock.Instant)? = nil
    ) {
        self.makeClient = makeClient
        self.now = now ?? { ContinuousClock.now }
    }

    /// The icon if it is known. Otherwise starts fetching it from `endpoint` (unless a fetch
    /// is already running or there is no endpoint) and returns nil.
    public func entry(for key: Key, endpoint: DaemonEndpoint?) -> Entry? {
        if let entry = entries[key] { return entry }
        if let retry = failedUntil[key], now() < retry { return nil }
        if let endpoint, inFlight[key] == nil {
            fetch(key, from: endpoint)
        }
        return nil
    }

    /// Like `entry`, but waits for the fetch it started or joined.
    public func load(_ key: Key, endpoint: DaemonEndpoint?) async -> Entry? {
        if let entry = entry(for: key, endpoint: endpoint) { return entry }
        await inFlight[key]?.value
        return entries[key]
    }

    private func fetch(_ key: Key, from endpoint: DaemonEndpoint) {
        requestCount += 1
        let client = makeClient(endpoint)
        inFlight[key] = Task { [weak self] in
            let result: Result<Data, any Error>
            do {
                result = .success(try await client.appIcon(bundlePath: key.bundlePath))
            } catch {
                result = .failure(error)
            }
            self?.finish(key, result, endpoint: endpoint)
        }
    }

    private func finish(_ key: Key, _ result: Result<Data, any Error>, endpoint: DaemonEndpoint) {
        inFlight[key] = nil
        switch result {
        case .success(let png):
            entries[key] = png.isEmpty ? .noIcon : .png(png)
            failedUntil[key] = nil
        case .failure(let error):
            failedUntil[key] = now() + Self.retryAfter
            logger.error(
                "GetAppIcon \(key.bundlePath, privacy: .public) on \(key.machineID, privacy: .public) via \(endpoint, privacy: .public) failed: \(error)"
            )
        }
    }
}
