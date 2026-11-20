import Foundation
import Testing

@testable import ComputaCore

@MainActor
@Suite struct SessionStoreTests {
    let clock = ManualSleep()

    func makeStore(_ fake: FakeMonitorClient) -> SessionStore {
        let clock = clock
        return SessionStore(endpoint: .local, makeClient: { _ in fake }, sleep: { try await clock.sleep($0) })
    }

    /// Lets queued tasks run, so a stream that should not start has had the chance to.
    func settle() async throws { try await Task.sleep(for: .milliseconds(20)) }

    @Test func dashboardStreamsOnlyOnTheSessionsTab() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = makeStore(fake)

        // Sessions tab selected, window closed: nothing.
        store.setTab(.sessions)
        try await settle()
        #expect(fake.sessionIntervals.isEmpty)

        // Open on another tab: still nothing.
        store.setTab(.memory)
        store.setDashboardOpen(true)
        try await settle()
        #expect(fake.sessionIntervals.isEmpty)
        #expect(!store.isStreaming)

        // The Sessions tab starts the stream at 2 s.
        store.setTab(.sessions)
        try await eventually("connected") { store.state == .connected }
        #expect(fake.sessionIntervals == [2000])
        #expect(store.snapshot == Fixtures.sessions)

        // Another tab stops it and drops the snapshot.
        store.setTab(.cpu)
        #expect(!store.isStreaming)
        #expect(store.snapshot == nil)
        try await eventually("cancelled on tab switch") { fake.activeSessionStreams == 0 }

        // Back on Sessions, then the window closes.
        store.setTab(.sessions)
        try await eventually("connected again") { store.state == .connected }
        store.setDashboardOpen(false)
        #expect(store.snapshot == nil)
        try await eventually("cancelled on close") { fake.activeSessionStreams == 0 }
        #expect(fake.sessionIntervals.count == 2)
    }

    @Test func popoverStreamsOnAnyTabAndSharesTheStreamWithTheDashboard() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = makeStore(fake)

        store.setTab(.disk)
        store.setPopoverOpen(true)
        try await eventually("connected for the popover") { store.state == .connected }
        #expect(fake.sessionIntervals == [2000])

        // The dashboard opens on Sessions while the popover is open: the same stream.
        store.setTab(.sessions)
        store.setDashboardOpen(true)
        try await settle()
        #expect(fake.sessionIntervals == [2000])
        #expect(fake.activeSessionStreams == 1)

        // The popover closes; the dashboard still wants it.
        store.setPopoverOpen(false)
        try await settle()
        #expect(store.isStreaming)
        #expect(fake.sessionIntervals == [2000])
        #expect(fake.activeSessionStreams == 1)

        // The popover opens again, then the dashboard closes: still the same stream.
        store.setPopoverOpen(true)
        store.setDashboardOpen(false)
        try await settle()
        #expect(fake.sessionIntervals == [2000])
        #expect(store.snapshot == Fixtures.sessions)

        // Nobody wants it.
        store.setPopoverOpen(false)
        #expect(!store.isStreaming)
        #expect(store.snapshot == nil)
        try await eventually("cancelled") { fake.activeSessionStreams == 0 }
    }

    @Test func stopClearsBothSurfaces() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = makeStore(fake)
        store.setTab(.sessions)
        store.setDashboardOpen(true)
        store.setPopoverOpen(true)
        try await eventually("connected") { store.state == .connected }
        store.stop()
        #expect(!store.isPopoverOpen)
        #expect(!store.isDashboardOpen)
        #expect(!store.isStreaming)
        try await eventually("cancelled") { fake.activeSessionStreams == 0 }
    }

    @Test func unimplementedMeansTheDaemonNeedsAnUpdateAndRetriesSlowly() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        fake.scriptSessions([.fail(unimplemented)])
        let store = makeStore(fake)
        store.setPopoverOpen(true)
        try await eventually("failed") { store.state != .connecting }
        guard case .daemonNotRunning(let problem) = store.state else {
            Issue.record("expected daemonNotRunning, got \(store.state)")
            return
        }
        #expect(problem.kind == .unsupported)
        #expect(problem.summary.contains("Update the daemon"))
        #expect(store.snapshot == nil)
        // The popover's row stays hidden rather than showing an error.
        #expect(ClaudeUsage.popoverText(store.snapshot) == nil)
        try await eventually("retry wait") { clock.waitingCount == 1 }
        #expect(clock.requested == [SessionStore.unsupportedRetryDelay])
        store.stop()
        clock.releaseAll()
    }

    @Test func reconnectsAfterAFailureAndNeverShowsAStaleSnapshot() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        fake.scriptSessions([.fail(unavailable), .fail(unavailable)])
        let store = makeStore(fake)
        store.setPopoverOpen(true)

        try await eventually("first retry wait") { clock.waitingCount == 1 }
        guard case .daemonNotRunning(let problem) = store.state else {
            Issue.record("expected daemonNotRunning, got \(store.state)")
            return
        }
        #expect(problem.kind == .unreachable)
        #expect(store.snapshot == nil)
        #expect(clock.requested == [SessionStore.retryDelay])

        fake.scriptSessions([.sendThenHang([Fixtures.sessionsRexDown, Fixtures.sessions])])
        clock.releaseAll()
        try await eventually("newest snapshot") { store.snapshot == Fixtures.sessions }
        #expect(fake.sessionIntervals.count == 2)
        #expect(store.state == .connected)
        store.stop()
        #expect(store.snapshot == nil)
    }

    @Test func rexBeingDownIsAConnectedSnapshotNotAFailure() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        fake.scriptSessions([.sendThenHang([Fixtures.sessionsRexDown])])
        let store = makeStore(fake)
        store.setPopoverOpen(true)
        try await eventually("connected") { store.state == .connected }
        #expect(store.snapshot?.rex.reachable == false)
        #expect(store.snapshot?.rex.problem.isEmpty == false)
        #expect(clock.requested.isEmpty)
        store.stop()
    }
}
