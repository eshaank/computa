import Foundation
import Observation
import os

/// Fetches chart history while the dashboard is open, and fetches it again every
/// `refreshInterval`. Nothing is fetched while the dashboard is closed.
@MainActor
@Observable
public final class HistoryStore {
    /// Time between fetches while the dashboard is open.
    public static let refreshInterval: Duration = .seconds(5)
    /// The most points asked for; the chart has this many bar slots.
    public static let maxPoints: UInt32 = 90

    /// The newest history for `range`. Nil before the first answer, after a failure, after the
    /// range changed and while closed, so a chart never shows numbers for the wrong window.
    public private(set) var series: HistorySeries?
    /// Why the last fetch failed. Cleared by the next success.
    public private(set) var problem: DaemonProblem?
    public private(set) var range: HistoryRange = .fifteenMinutes
    public private(set) var isOpen = false
    public private(set) var endpoint: DaemonEndpoint
    /// How many fetches have finished, successful or not. For tests and logging.
    public private(set) var fetchCount = 0

    /// True while the fetch loop runs.
    public var isRunning: Bool { loop != nil }

    @ObservationIgnored private let makeClient: MonitorClientFactory
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let logger = Logger(subsystem: "app.computa.Computa", category: "history")

    /// - Parameter sleep: Waits between fetches. Tests pass one they control.
    public init(
        endpoint: DaemonEndpoint,
        makeClient: @escaping MonitorClientFactory = { DaemonClient(endpoint: $0) },
        sleep: SleepFunction? = nil
    ) {
        self.endpoint = endpoint
        self.makeClient = makeClient
        self.sleep = sleep ?? realSleep
    }

    /// Starts fetching when the dashboard opens and stops when it closes.
    public func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        if open { restart() } else { stopLoop() }
    }

    /// Switches the chart's time window and fetches at once.
    public func setRange(_ newRange: HistoryRange) {
        guard newRange != range else { return }
        range = newRange
        series = nil
        if isOpen { restart() }
    }

    /// Switches to another daemon.
    public func setEndpoint(_ newEndpoint: DaemonEndpoint) {
        guard newEndpoint != endpoint else { return }
        endpoint = newEndpoint
        series = nil
        problem = nil
        if isOpen { restart() }
    }

    // MARK: - The loop

    private func stopLoop() {
        generation += 1
        loop?.cancel()
        loop = nil
        series = nil
        problem = nil
    }

    private func restart() {
        generation += 1
        loop?.cancel()
        let current = generation
        let endpoint = endpoint
        let range = range
        loop = Task { [weak self] in
            await self?.run(generation: current, endpoint: endpoint, range: range)
        }
    }

    private func run(generation current: Int, endpoint: DaemonEndpoint, range: HistoryRange) async {
        while isCurrent(current) {
            await fetch(generation: current, endpoint: endpoint, range: range)
            guard isCurrent(current) else { return }
            do {
                try await sleep(Self.refreshInterval)
            } catch {
                // Only cancellation ends the wait, and cancellation means the loop was replaced.
                logger.debug("history wait ended: \(error)")
                return
            }
        }
    }

    private func fetch(generation current: Int, endpoint: DaemonEndpoint, range: HistoryRange) async {
        do {
            let result = try await makeClient(endpoint).history(
                windowSeconds: range.windowSeconds, maxPoints: Self.maxPoints
            )
            guard isCurrent(current) else { return }
            series = result
            problem = nil
        } catch {
            guard isCurrent(current) else { return }
            logger.error("GetHistory (\(range.windowSeconds) s) from \(endpoint, privacy: .public) failed: \(error)")
            series = nil
            problem = DaemonProblem(error: error, endpoint: endpoint)
        }
        fetchCount += 1
    }

    private func isCurrent(_ current: Int) -> Bool {
        current == generation && !Task.isCancelled
    }
}
