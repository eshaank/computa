import Foundation
import Observation
import os

/// Keeps a live connection to the daemon and exposes what it reports.
///
/// The store streams samples, and when the stream fails it waits `retryDelay` and tries again,
/// for as long as it runs. Nothing outside needs to restart it.
@MainActor
@Observable
public final class MonitorStore {
    /// Places that show live numbers. While any of them is open, samples arrive every second.
    public enum Surface: Hashable, Sendable {
        case popover, dashboard
    }

    /// Wait between connection attempts. Recovery is within this plus one connection attempt.
    public static let retryDelay: Duration = .seconds(1)
    /// Sample interval while the popover or the dashboard is open.
    public static let openIntervalMilliseconds: UInt32 = 1000
    /// Sample interval while only the menu bar label shows numbers.
    public static let closedIntervalMilliseconds: UInt32 = 5000

    public private(set) var state: ConnectionState = .connecting
    /// Facts about the daemon's machine, once it has answered `GetHost`.
    public private(set) var host: HostInfo?
    /// Why `host` is missing, if asking for it failed.
    public private(set) var hostProblem: DaemonProblem?
    public private(set) var endpoint: DaemonEndpoint
    /// The interval the current stream asked for.
    public private(set) var intervalMilliseconds: UInt32 = closedIntervalMilliseconds
    /// True while there is no daemon to talk to (a remote machine's tunnel is not up).
    public private(set) var isSuspended = false

    /// The newest sample, only while connected. Never a stale one.
    public var sample: SystemSample? { state.isConnected ? latestSample : nil }

    private var latestSample: SystemSample?
    @ObservationIgnored private let makeClient: MonitorClientFactory
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var openSurfaces: Set<Surface> = []
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private let logger = Logger(subsystem: "app.computa.Computa", category: "connection")

    /// - Parameters:
    ///   - endpoint: Where the daemon is.
    ///   - makeClient: Makes a client for an address; called once per connection attempt.
    ///   - sleep: Waits between attempts. Tests pass one they control.
    public init(
        endpoint: DaemonEndpoint,
        makeClient: @escaping MonitorClientFactory = { DaemonClient(endpoint: $0) },
        sleep: SleepFunction? = nil
    ) {
        self.endpoint = endpoint
        self.makeClient = makeClient
        self.sleep = sleep ?? realSleep
    }

    /// Starts streaming. Calling it again restarts the stream.
    public func start() {
        isStarted = true
        if !isSuspended { restart() }
    }

    /// Stops streaming and forgets the latest sample.
    public func stop() {
        isStarted = false
        generation += 1
        loop?.cancel()
        loop = nil
        latestSample = nil
        state = .connecting
    }

    /// Records that a surface opened or closed, and changes the sample rate if that changes it.
    public func setOpen(_ open: Bool, _ surface: Surface) {
        if open { openSurfaces.insert(surface) } else { openSurfaces.remove(surface) }
        let wanted = openSurfaces.isEmpty ? Self.closedIntervalMilliseconds : Self.openIntervalMilliseconds
        guard wanted != intervalMilliseconds else { return }
        logger.info("sample interval \(self.intervalMilliseconds) ms -> \(wanted) ms (open: \(self.openSurfaces.count))")
        intervalMilliseconds = wanted
        if loop != nil { restart() }
    }

    /// Pauses streaming while there is no daemon to reach, dropping the sample and the facts
    /// about the machine, so nothing stale shows. Resuming streams again if started.
    public func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            generation += 1
            loop?.cancel()
            loop = nil
            host = nil
            hostProblem = nil
            latestSample = nil
            state = .connecting
        } else if isStarted {
            restart()
        }
    }

    /// Switches to another daemon. Facts about the old one are dropped.
    public func setEndpoint(_ newEndpoint: DaemonEndpoint) {
        guard newEndpoint != endpoint else { return }
        logger.info("daemon address \(self.endpoint, privacy: .public) -> \(newEndpoint, privacy: .public)")
        endpoint = newEndpoint
        host = nil
        hostProblem = nil
        latestSample = nil
        state = .connecting
        if loop != nil { restart() }
    }

    // MARK: - The loop

    /// Starts a new loop. The old one is cancelled; its late callbacks carry an old generation
    /// and are ignored, so a restart never shows as a failure.
    private func restart() {
        generation += 1
        loop?.cancel()
        let current = generation
        let endpoint = endpoint
        let interval = intervalMilliseconds
        loop = Task { [weak self] in
            await self?.run(generation: current, endpoint: endpoint, interval: interval)
        }
    }

    private func run(generation current: Int, endpoint: DaemonEndpoint, interval: UInt32) async {
        while isCurrent(current) {
            let client = makeClient(endpoint)
            await loadHostIfNeeded(client, generation: current, endpoint: endpoint)
            await stream(client, generation: current, endpoint: endpoint, interval: interval)
            guard isCurrent(current) else { return }
            do {
                try await sleep(Self.retryDelay)
            } catch {
                // Only cancellation ends the wait, and cancellation means a newer loop runs.
                logger.debug("retry wait ended: \(error)")
                return
            }
        }
    }

    private func stream(_ client: any MonitorClient, generation current: Int, endpoint: DaemonEndpoint, interval: UInt32) async {
        do {
            try await client.watchSystem(intervalMilliseconds: interval) { [weak self] sample in
                await self?.receive(sample, generation: current) ?? false
            }
            guard isCurrent(current) else { return }
            fail(.streamEnded(endpoint), generation: current)
        } catch {
            guard isCurrent(current) else { return }
            logger.error("stream from \(endpoint, privacy: .public) failed: \(error)")
            fail(DaemonProblem(error: error, endpoint: endpoint), generation: current)
        }
    }

    private func loadHostIfNeeded(_ client: any MonitorClient, generation current: Int, endpoint: DaemonEndpoint) async {
        guard host == nil else { return }
        do {
            let facts = try await client.host()
            guard isCurrent(current) else { return }
            host = facts
            hostProblem = nil
        } catch {
            guard isCurrent(current) else { return }
            logger.error("GetHost from \(endpoint, privacy: .public) failed: \(error)")
            hostProblem = DaemonProblem(error: error, endpoint: endpoint)
        }
    }

    private func receive(_ newSample: SystemSample, generation current: Int) -> Bool {
        guard isCurrent(current) else { return false }
        latestSample = newSample
        if state != .connected {
            logger.info("connected to \(self.endpoint, privacy: .public)")
            state = .connected
        }
        return true
    }

    private func fail(_ problem: DaemonProblem, generation current: Int) {
        guard isCurrent(current) else { return }
        latestSample = nil
        state = .daemonNotRunning(problem)
    }

    private func isCurrent(_ current: Int) -> Bool {
        current == generation && !Task.isCancelled
    }
}
