import Foundation
import Observation
import os

/// The last thing an action did, shown in the Sessions tab until it clears itself.
public struct RexActionOutcome: Sendable, Equatable {
    public var succeeded: Bool
    /// A sentence: what happened, or what to do about the failure.
    public var text: String

    public init(succeeded: Bool, text: String) {
        self.succeeded = succeeded
        self.text = text
    }
}

/// Runs Rex actions for the dashboard: what is in progress, and the last outcome.
///
/// Never runs two actions for the same session or pane at once. A pane that was closed stays
/// marked in progress for a moment, because its row only leaves the list with the daemon's next
/// snapshot.
@MainActor
@Observable
public final class RexActionsModel {
    /// How long a success shows.
    public static let successDuration: Duration = .seconds(4)
    /// How long an error shows. Longer, because it says what to do.
    public static let errorDuration: Duration = .seconds(10)
    /// How long a closed pane stays marked, covering the daemon's 2 s snapshot interval.
    public static let closedGrace: Duration = .seconds(5)

    /// Targets with an action running, or panes just closed.
    public private(set) var busy: Set<RexActionTarget> = []
    public private(set) var outcome: RexActionOutcome?

    @ObservationIgnored private let runner: any RexActionRunning
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var outcomeGeneration = 0
    @ObservationIgnored private var clearTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "app.computa.Computa", category: "rex")

    /// - Parameter sleep: Waits before an outcome or a closed pane clears. Tests pass one they control.
    public init(
        runner: any RexActionRunning,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.runner = runner
        self.sleep = sleep
    }

    public func isBusy(_ target: RexActionTarget) -> Bool { busy.contains(target) }

    /// Starts an action unless one is already running for its target.
    ///
    /// - Returns: The running task, or nil when the request was ignored.
    @discardableResult
    public func run(_ action: RexAction) -> Task<Void, Never>? {
        let target = action.target
        guard !busy.contains(target) else {
            logger.info("\(action.name, privacy: .public) ignored: one is already running for \(String(describing: target), privacy: .public)")
            return nil
        }
        busy.insert(target)
        return Task { await perform(action) }
    }

    private func perform(_ action: RexAction) async {
        let target = action.target
        do {
            let result = try await runner.run(action)
            logger.info("\(action.name, privacy: .public) succeeded: \(String(describing: result), privacy: .public)")
            show(RexActionOutcome(succeeded: true, text: result.summary), for: Self.successDuration)
            if case .closedPane = result {
                release(target, after: Self.closedGrace)
            } else {
                busy.remove(target)
            }
        } catch {
            logger.error("\(action.name, privacy: .public) failed: \(error.description, privacy: .public)")
            show(RexActionOutcome(succeeded: false, text: error.description), for: Self.errorDuration)
            busy.remove(target)
        }
    }

    private func show(_ newOutcome: RexActionOutcome, for duration: Duration) {
        outcomeGeneration += 1
        let generation = outcomeGeneration
        outcome = newOutcome
        clearTask?.cancel()
        clearTask = Task { [weak self, sleep, logger] in
            do {
                try await sleep(duration)
            } catch {
                // Cancelled because a newer outcome replaced this one, which clears itself.
                logger.debug("outcome clear wait ended early: \(error)")
                return
            }
            guard let self, self.outcomeGeneration == generation else { return }
            self.outcome = nil
        }
    }

    private func release(_ target: RexActionTarget, after duration: Duration) {
        Task { [weak self, sleep] in
            do {
                try await sleep(duration)
            } catch {
                self?.logger.debug("closed-pane wait ended early: \(error)")
            }
            self?.busy.remove(target)
        }
    }
}
