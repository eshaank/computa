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
    func settle() async throws { try await pause(for: .milliseconds(20)) }

    @Test func streamsOnlyWhileTheDashboardIsOpenOnAProcessTab() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = makeStore(fake)

        // A process tab is selected but the window is closed.
        store.setTab(.memory)
        try await settle()
        #expect(fake.processIntervals.isEmpty)
        #expect(!store.isStreaming)

        // Open on the disk tab: still nothing.
        store.setTab(.disk)
        store.setDashboardOpen(true)
        try await settle()
        #expect(fake.processIntervals.isEmpty)

        // The CPU tab starts the stream at 2 s, without traffic.
        store.setTab(.cpu)
        try await eventually("connected") { store.state == .connected }
        #expect(fake.processIntervals == [2000])
        #expect(fake.processTrafficRequests == [false])
        #expect(store.snapshot == Fixtures.processes)

        // Switching between the two memory and CPU tabs keeps the same stream.
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

    @Test func asksForTrafficOnlyOnTheNetTabAndRestartsWhenThatChanges() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        var withoutTraffic = Fixtures.processes
        withoutTraffic.network = nil
        fake.scriptProcesses([.sendThenHang([withoutTraffic])])
        let store = makeStore(fake)
        store.setDashboardOpen(true)
        store.setTab(.memory)
        try await eventually("connected") { store.state == .connected }
        #expect(fake.processTrafficRequests == [false])
        #expect(!store.isStreamingTraffic)

        // To the Net tab: a new stream that asks for traffic, and the old snapshot is gone at once.
        fake.scriptProcesses([.sendThenHang([Fixtures.processes])])
        store.setTab(.network)
        #expect(store.snapshot == nil)
        #expect(store.isStreamingTraffic)
        try await eventually("connected with traffic") { store.state == .connected }
        #expect(fake.processTrafficRequests == [false, true])
        #expect(store.snapshot?.network == ProcessNetworkStatus(available: true))
        try await eventually("old stream cancelled") { fake.activeProcessStreams == 1 }

        // Back to CPU: a stream without traffic again, never showing the Net tab's snapshot.
        fake.scriptProcesses([.sendThenHang([withoutTraffic])])
        store.setTab(.cpu)
        #expect(store.snapshot == nil)
        try await eventually("connected without traffic") { store.state == .connected }
        #expect(fake.processTrafficRequests == [false, true, false])
        #expect(store.snapshot?.network == nil)
        try await eventually("one stream") { fake.activeProcessStreams == 1 }
        store.stop()
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
