import Foundation
import Testing

@testable import ComputaCore

/// Stores built with their real wait, cancelled in the middle of it. In the app that is: the
/// daemon is down, the store is waiting to retry, and a window opens or closes. These aborted
/// ("freed pointer was not the last allocation") while the wait was `pause(for:)`; see
/// `pause(for:)`. `CompletedWaitTests` covers a wait that ends by itself.
@MainActor
@Suite struct CancelledWaitTests {
    @Test func openingAWindowDuringAMonitorRetryWaitRestartsTheStream() async throws {
        let fake = FakeMonitorClient([.fail(unavailable), .fail(unavailable)])
        let store = MonitorStore(endpoint: .local, makeClient: { _ in fake })
        store.start()
        try await eventually("first attempt failed") { store.state != .connecting }
        try await pause(for: .milliseconds(50))
        // Changes the sample interval, which cancels the retry wait and starts a new stream.
        store.setOpen(true, .popover)
        try await eventually("second attempt") { fake.attempts == 2 }
        store.stop()
    }

    @Test func stoppingDuringAMonitorRetryWaitStopsConnecting() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = MonitorStore(endpoint: .local, makeClient: { _ in fake })
        store.start()
        try await eventually("first attempt failed") { store.state != .connecting }
        try await pause(for: .milliseconds(50))
        store.stop()
        try await pause(for: .milliseconds(100))
        #expect(store.state == .connecting)
        #expect(fake.attempts == 1)
    }

    @Test func closingTheDashboardDuringAHistoryWaitStopsFetching() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = HistoryStore(endpoint: .local, makeClient: { _ in fake })
        store.setOpen(true)
        try await eventually("first fetch") { store.fetchCount == 1 }
        try await pause(for: .milliseconds(50))
        store.setOpen(false)
        try await pause(for: .milliseconds(100))
        #expect(!store.isRunning)
        #expect(store.fetchCount == 1)
    }

    @Test func closingTheDashboardDuringAProcessRetryWaitStopsTheStream() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        fake.scriptProcesses([.fail(unavailable)])
        let store = ProcessStore(endpoint: .local, makeClient: { _ in fake })
        store.setDashboardOpen(true)
        try await eventually("first attempt failed") { store.state != .connecting }
        try await pause(for: .milliseconds(50))
        store.setDashboardOpen(false)
        try await pause(for: .milliseconds(100))
        #expect(!store.isStreaming)
        #expect(fake.processIntervals.count == 1)
    }

    @Test func closingThePopoverDuringASessionRetryWaitStopsTheStream() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        fake.scriptSessions([.fail(unavailable)])
        let store = SessionStore(endpoint: .local, makeClient: { _ in fake })
        store.setPopoverOpen(true)
        try await eventually("first attempt failed") { store.state != .connecting }
        try await pause(for: .milliseconds(50))
        store.setPopoverOpen(false)
        try await pause(for: .milliseconds(100))
        #expect(!store.isStreaming)
        #expect(fake.sessionIntervals.count == 1)
    }

    @Test func aNewOutcomeDuringTheClearWaitReplacesTheOldOne() async throws {
        let runner = FakeRexRunner()
        let model = RexActionsModel(runner: runner)
        let first = model.run(.openProcessViewer(sessionID: "session:01a1"))
        try await eventually("first running") { runner.waitingCount == 1 }
        runner.finish(.success(.openedProcessViewer(program: "/usr/bin/top", windowID: "window:1")))
        await first?.value
        #expect(model.outcome?.succeeded == true)
        try await pause(for: .milliseconds(50))

        // The first outcome's clear wait is still running; a second outcome cancels it.
        let second = model.run(.openProcessViewer(sessionID: "session:01a1"))
        try await eventually("second running") { runner.waitingCount == 1 }
        runner.finish(.failure(.actionsNotInstalled))
        await second?.value
        try await pause(for: .milliseconds(100))
        #expect(model.outcome?.succeeded == false)
    }

    @Test func suspendingDuringAMonitorRetryWaitStopsConnecting() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = MonitorStore(endpoint: .local, makeClient: { _ in fake })
        store.start()
        try await eventually("first attempt failed") { store.state != .connecting }
        store.setSuspended(true)
        try await pause(for: .milliseconds(100))
        #expect(store.state == .connecting)
        #expect(fake.attempts == 1)
        store.stop()
    }
}
