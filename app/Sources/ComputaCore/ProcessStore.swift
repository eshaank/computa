import Foundation
import Observation
import os

/// Streams the process list, only while the dashboard is open on a tab that shows it. Reading
/// every process costs the daemon work, so the stream stops as soon as nobody looks.
///
/// Like `MonitorStore`, when the stream fails it waits and tries again for as long as it is
/// wanted.
@MainActor
@Observable
public final class ProcessStore {
    /// Time between snapshots.
    public static let intervalMilliseconds: UInt32 = 2000
    /// Wait before reconnecting after a failure.
    public static let retryDelay: Duration = .seconds(1)
    /// Wait before asking again when the daemon does not offer the call: an update is needed,
    /// which takes longer than a restart.
    public static let unsupportedRetryDelay: Duration = .seconds(10)

    public private(set) var state: ConnectionState = .connecting
    public private(set) var isDashboardOpen = false
    public private(set) var tab: DashboardTab = .cpu
    public private(set) var endpoint: DaemonEndpoint

    /// The newest snapshot, only while connected. Never a stale one.
    public var snapshot: ProcessSnapshot? { state.isConnected ? latest : nil }
    /// True while the stream is wanted and running.
    public var isStreaming: Bool { loop != nil }

    private var latest: ProcessSnapshot?
    @ObservationIgnored private let makeClient: MonitorClientFactory
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let logger = Logger(subsystem: "app.computa.Computa", category: "processes")

    /// - Parameter sleep: Waits between attempts. Tests pass one they control.
    public init(
        endpoint: DaemonEndpoint,
        makeClient: @escaping MonitorClientFactory = { DaemonClient(endpoint: $0) },
        sleep: SleepFunction? = nil
    ) {
        self.endpoint = endpoint
        self.makeClient = makeClient
        self.sleep = sleep ?? realSleep
    }

    public func setDashboardOpen(_ open: Bool) {
        isDashboardOpen = open
        update()
    }

    public func setTab(_ newTab: DashboardTab) {
        tab = newTab
        update()
    }

    /// Switches to another daemon.
    public func setEndpoint(_ newEndpoint: DaemonEndpoint) {
        guard newEndpoint != endpoint else { return }
        endpoint = newEndpoint
        if loop != nil {
            stopLoop()
            update()
        }
    }

    /// Stops streaming, whatever is showing. For quitting.
    public func stop() {
        isDashboardOpen = false
        stopLoop()
    }

    private var isWanted: Bool { isDashboardOpen && tab.showsProcesses }

    private func update() {
        if isWanted, loop == nil {
            logger.info("process stream starting (tab \(self.tab.rawValue, privacy: .public))")
            restart()
        } else if !isWanted, loop != nil {
            logger.info("process stream stopping")
            stopLoop()
        }
    }

    // MARK: - The loop

    private func stopLoop() {
        generation += 1
        loop?.cancel()
        loop = nil
        latest = nil
        state = .connecting
    }

    private func restart() {
        generation += 1
        loop?.cancel()
        let current = generation
        let endpoint = endpoint
        loop = Task { [weak self] in
            await self?.run(generation: current, endpoint: endpoint)
        }
    }

    private func run(generation current: Int, endpoint: DaemonEndpoint) async {
        while isCurrent(current) {
            await stream(makeClient(endpoint), generation: current, endpoint: endpoint)
            guard isCurrent(current) else { return }
            let unsupported = if case .daemonNotRunning(let problem) = state { problem.kind == .unsupported } else { false }
            do {
                try await sleep(unsupported ? Self.unsupportedRetryDelay : Self.retryDelay)
            } catch {
                // Only cancellation ends the wait, and cancellation means the loop was replaced.
                logger.debug("process retry wait ended: \(error)")
                return
            }
        }
    }

    private func stream(_ client: any MonitorClient, generation current: Int, endpoint: DaemonEndpoint) async {
        do {
            try await client.watchProcesses(intervalMilliseconds: Self.intervalMilliseconds) { [weak self] snapshot in
                await self?.receive(snapshot, generation: current) ?? false
            }
            guard isCurrent(current) else { return }
            fail(.streamEnded(endpoint), generation: current)
        } catch {
            guard isCurrent(current) else { return }
            logger.error("WatchProcesses from \(endpoint, privacy: .public) failed: \(error)")
            fail(DaemonProblem(error: error, endpoint: endpoint), generation: current)
        }
    }

    private func receive(_ snapshot: ProcessSnapshot, generation current: Int) -> Bool {
        guard isCurrent(current) else { return false }
        latest = snapshot
        if state != .connected { state = .connected }
        return true
    }

    private func fail(_ problem: DaemonProblem, generation current: Int) {
        guard isCurrent(current) else { return }
        latest = nil
        state = .daemonNotRunning(problem)
    }

    private func isCurrent(_ current: Int) -> Bool {
        current == generation && !Task.isCancelled
    }
}
