import Foundation
import Testing

@testable import ComputaCore

/// Stores built with their real wait, cancelled in the middle of it. A default-argument sleep
/// closure used to crash the process here ("freed pointer was not the last allocation"). In the
/// app that is: the daemon is down, the store is waiting to retry, and a window opens or closes.
@MainActor
@Suite struct CancelledWaitTests {
    @Test func openingAWindowDuringAMonitorRetryWaitRestartsTheStream() async throws {
        let fake = FakeMonitorClient([.fail(unavailable), .fail(unavailable)])
        let store = MonitorStore(endpoint: .local, makeClient: { _ in fake })
        store.start()
        try await eventually("first attempt failed") { store.state != .connecting }
        try await Task.sleep(for: .milliseconds(50))
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
        try await Task.sleep(for: .milliseconds(50))
        store.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.state == .connecting)
        #expect(fake.attempts == 1)
    }
}
