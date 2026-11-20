import Foundation
import Synchronization
import Testing

@testable import ComputaCore

/// A runner whose actions finish only when the test says so.
final class FakeRexRunner: RexActionRunning {
    private struct State {
        var actions: [RexAction] = []
        var waiting: [CheckedContinuation<Result<RexActionResult, RexActionError>, Never>] = []
    }

    private let state = Mutex(State())

    var actions: [RexAction] { state.withLock { $0.actions } }
    var waitingCount: Int { state.withLock { $0.waiting.count } }

    func run(_ action: RexAction) async throws(RexActionError) -> RexActionResult {
        let result = await withCheckedContinuation { continuation in
            state.withLock {
                $0.actions.append(action)
                $0.waiting.append(continuation)
            }
        }
        return try result.get()
    }

    /// Finishes the oldest running action.
    func finish(_ result: Result<RexActionResult, RexActionError>) {
        let next = state.withLock { $0.waiting.isEmpty ? nil : $0.waiting.removeFirst() }
        next?.resume(returning: result)
    }
}

@MainActor
@Suite struct RexActionsModelTests {
    let clock = ManualSleep()
    let runner = FakeRexRunner()
    let close = RexAction.closePane(sessionID: "session:01a1", paneID: "block:01a1-a")
    let open = RexAction.openProcessViewer(sessionID: "session:01a1")

    func makeModel() -> RexActionsModel {
        let clock = clock
        return RexActionsModel(runner: runner, sleep: { try await clock.sleep($0) })
    }

    @Test func openingTheViewerShowsProgressThenSuccess() async throws {
        let model = makeModel()
        let task = model.run(open)
        #expect(model.isBusy(.session("session:01a1")))
        try await eventually("running") { runner.waitingCount == 1 }
        #expect(runner.actions == [open])

        runner.finish(.success(.openedProcessViewer(program: "/opt/homebrew/bin/btop", windowID: "window:9")))
        await task?.value
        #expect(!model.isBusy(.session("session:01a1")))
        #expect(model.outcome == RexActionOutcome(succeeded: true, text: "Opened btop in a new tab."))

        // The outcome clears itself after the success delay.
        try await eventually("clear wait") { clock.waitingCount == 1 }
        #expect(clock.requested == [RexActionsModel.successDuration])
        clock.releaseAll()
        try await eventually("cleared") { model.outcome == nil }
    }

    @Test func anErrorShowsItsSentenceAndFreesTheTarget() async throws {
        let model = makeModel()
        let task = model.run(close)
        try await eventually("running") { runner.waitingCount == 1 }
        runner.finish(.failure(.actionsNotInstalled))
        await task?.value
        #expect(model.outcome == RexActionOutcome(succeeded: false, text: RexActionError.actionsNotInstalled.description))
        #expect(!model.isBusy(.pane("block:01a1-a")))
        try await eventually("clear wait") { clock.waitingCount == 1 }
        #expect(clock.requested == [RexActionsModel.errorDuration])
        clock.releaseAll()
        try await eventually("cleared") { model.outcome == nil }
    }

    @Test func aSecondCloseOfTheSamePaneIsIgnoredWhileOneRuns() async throws {
        let model = makeModel()
        let first = model.run(close)
        #expect(first != nil)
        #expect(model.run(close) == nil)
        // A different pane is not blocked.
        let other = RexAction.closePane(sessionID: "session:01a1", paneID: "block:01a1-b")
        let second = model.run(other)
        #expect(second != nil)
        try await eventually("both running") { runner.waitingCount == 2 }
        #expect(runner.actions.count == 2)
        #expect(runner.actions.contains(close) && runner.actions.contains(other))
        runner.finish(.failure(.failed("one")))
        runner.finish(.failure(.failed("two")))
        await first?.value
        await second?.value
    }

    @Test func aClosedPaneStaysBusyUntilTheGraceEnds() async throws {
        let model = makeModel()
        let task = model.run(close)
        try await eventually("running") { runner.waitingCount == 1 }
        runner.finish(.success(.closedPane(paneID: "block:01a1-a", sessionID: "session:01a1")))
        await task?.value
        #expect(model.outcome?.text == "Closed the pane.")
        #expect(model.isBusy(.pane("block:01a1-a")))
        #expect(model.run(close) == nil)
        try await eventually("two waits") { clock.waitingCount == 2 }
        #expect(Set(clock.requested) == [RexActionsModel.successDuration, RexActionsModel.closedGrace])
        clock.releaseAll()
        try await eventually("released") { !model.isBusy(.pane("block:01a1-a")) }
    }

    @Test func anOldClearTimerDoesNotWipeANewerOutcome() async throws {
        let model = makeModel()
        let first = model.run(open)
        try await eventually("first running") { runner.waitingCount == 1 }
        runner.finish(.failure(.timedOut(.seconds(10))))
        await first?.value
        try await eventually("first clear wait") { clock.waitingCount == 1 }

        let second = model.run(open)
        try await eventually("second running") { runner.waitingCount == 1 }
        runner.finish(.success(.openedProcessViewer(program: "/usr/bin/top", windowID: "w")))
        await second?.value
        try await eventually("second clear wait") { clock.waitingCount == 2 }
        #expect(model.outcome?.text == "Opened top in a new tab.")
        // The first outcome's timer ends: the newer outcome stays.
        clock.releaseFirst()
        try await Task.sleep(for: .milliseconds(30))
        #expect(model.outcome?.text == "Opened top in a new tab.")
        // Its own timer clears it.
        clock.releaseFirst()
        try await eventually("cleared") { model.outcome == nil }
    }
}
