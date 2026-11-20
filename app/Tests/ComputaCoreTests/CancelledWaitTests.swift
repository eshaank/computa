import Foundation
import Testing

@testable import ComputaCore

/// Stores built with their real wait, cancelled in the middle of it. A default-argument sleep
/// closure used to crash the process here ("freed pointer was not the last allocation"), which
/// is what closing the dashboard or switching machines does.
@MainActor
@Suite struct CancelledWaitTests {
    @Test func closingTheDashboardDuringAHistoryWaitStopsFetching() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = HistoryStore(endpoint: .local, makeClient: { _ in fake })
        store.setOpen(true)
        try await eventually("first fetch") { store.fetchCount == 1 }
        try await Task.sleep(for: .milliseconds(50))
        store.setOpen(false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!store.isRunning)
        #expect(store.fetchCount == 1)
    }

    @Test func suspendingDuringAMonitorRetryWaitStopsConnecting() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = MonitorStore(endpoint: .local, makeClient: { _ in fake })
        store.start()
        try await eventually("first attempt failed") { store.state != .connecting }
        store.setSuspended(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.state == .connecting)
        #expect(fake.attempts == 1)
        store.stop()
    }
}
