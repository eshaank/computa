import Foundation
import Testing

@testable import ComputaCore

@MainActor
@Suite struct ProcessStoreTests {
    let clock = ManualSleep()

    func makeStore(_ fake: FakeMonitorClient) -> ProcessStore {
        let clock = clock
        return ProcessStore(endpoint: .local, makeClient: { _ in fake }, sleep: { try await clock.sleep($0) })
    }

    /// Lets queued tasks run, so a stream that should not start has had the chance to.
    func settle() async throws { try await Task.sleep(for: .milliseconds(20)) }

    @Test func streamsOnlyWhileTheDashboardIsOpenOnTheCpuOrMemoryTab() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = makeStore(fake)

        // A process tab is selected but the window is closed.
        store.setTab(.memory)
        try await settle()
        #expect(fake.processIntervals.isEmpty)
        #expect(!store.isStreaming)

        // Open on the network tab: still nothing.
        store.setTab(.network)
        store.setDashboardOpen(true)
        try await settle()
        #expect(fake.processIntervals.isEmpty)

        // The CPU tab starts the stream at 2 s.
        store.setTab(.cpu)
        try await eventually("connected") { store.state == .connected }
        #expect(fake.processIntervals == [2000])
        #expect(store.snapshot == Fixtures.processes)

        // Switching between the two process tabs keeps the same stream.
        store.setTab(.memory)
        try await settle()
        #expect(fake.processIntervals == [2000])
        #expect(fake.activeProcessStreams == 1)

        // The disk tab stops it and drops the snapshot.
        store.setTab(.disk)
        #expect(!store.isStreaming)
        #expect(store.snapshot == nil)
        try await eventually("stream cancelled") { fake.activeProcessStreams == 0 }

        // Back on memory, then the window closes.
        store.setTab(.memory)
        try await eventually("connected again") { store.state == .connected }
        #expect(fake.processIntervals.count == 2)
        store.setDashboardOpen(false)
        #expect(store.snapshot == nil)
        try await eventually("stream cancelled on close") { fake.activeProcessStreams == 0 }
    }

    @Test func unimplementedMeansTheDaemonNeedsAnUpdate() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        fake.scriptProcesses([.fail(unimplemented)])
        let store = makeStore(fake)
        store.setDashboardOpen(true)
        try await eventually("failed") { store.state != .connecting }
        guard case .daemonNotRunning(let problem) = store.state else {
            Issue.record("expected daemonNotRunning, got \(store.state)")
            return
        }
        #expect(problem.kind == .unsupported)
        #expect(problem.summary.contains("Update the daemon"))
        #expect(store.snapshot == nil)
        try await eventually("retry wait") { clock.waitingCount == 1 }
        #expect(clock.requested == [ProcessStore.unsupportedRetryDelay])
        store.stop()
        clock.releaseAll()
    }

    @Test func reconnectsAfterAFailureAndNeverShowsAStaleSnapshot() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        fake.scriptProcesses([.fail(unavailable), .fail(unavailable)])
        let store = makeStore(fake)
        store.setDashboardOpen(true)

        try await eventually("first retry wait") { clock.waitingCount == 1 }
        guard case .daemonNotRunning(let problem) = store.state else {
            Issue.record("expected daemonNotRunning, got \(store.state)")
            return
        }
        #expect(problem.kind == .unreachable)
        #expect(store.snapshot == nil)
        #expect(clock.requested == [ProcessStore.retryDelay])

        fake.scriptProcesses([.sendThenHang([Fixtures.processes])])
        clock.releaseAll()
        try await eventually("connected") { store.state == .connected }
        #expect(fake.processIntervals.count == 2)
        #expect(store.snapshot?.groups.count == 12)
        store.stop()
        #expect(store.snapshot == nil)
    }
}
