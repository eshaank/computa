import Foundation
import Observation
import Testing

@testable import ComputaCore

@MainActor
@Suite struct MonitorStoreTests {
    let clock = ManualSleep()

    func makeStore(_ fake: FakeMonitorClient) -> MonitorStore {
        let clock = clock
        return MonitorStore(endpoint: .local, makeClient: { _ in fake }, sleep: { try await clock.sleep($0) })
    }

    @Test func goesFromConnectingToConnectedOnTheFirstSample() async throws {
        let fake = FakeMonitorClient([.sendThenHang([Fixtures.sample])])
        let store = makeStore(fake)
        #expect(store.state == .connecting)
        #expect(store.sample == nil)

        store.start()
        try await eventually("connected") { store.state == .connected }
        #expect(store.sample == Fixtures.sample)
        #expect(store.host == Fixtures.host)
        store.stop()
    }

    @Test func goesToDaemonNotRunningWhenTheStreamFailsAndDropsTheSample() async throws {
        let fake = FakeMonitorClient([.sendThenFail([Fixtures.sample], unavailable), .fail(unavailable)])
        let store = makeStore(fake)
        store.start()

        try await eventually("not running") {
            if case .daemonNotRunning = store.state { return true } else { return false }
        }
        guard case .daemonNotRunning(let problem) = store.state else { return }
        #expect(problem.kind == .unreachable)
        #expect(problem.summary.contains("127.0.0.1:7300"))
        #expect(store.sample == nil, "no stale numbers once the daemon is gone")
        store.stop()
        clock.releaseAll()
    }

    @Test func unimplementedDaemonIsReportedAsUnsupported() async throws {
        let store = makeStore(FakeMonitorClient([.fail(unimplemented)]))
        store.start()
        try await eventually("not running") { store.state != .connecting }
        guard case .daemonNotRunning(let problem) = store.state else {
            Issue.record("expected daemonNotRunning, got \(store.state)")
            return
        }
        #expect(problem.kind == .unsupported)
        store.stop()
        clock.releaseAll()
    }

    @Test func reconnectsAfterTheRetryDelayWhenTheDaemonComesBack() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = makeStore(fake)
        store.start()
        try await eventually("first retry wait") { clock.waitingCount == 1 }
        #expect(store.state != .connected)

        // Still down on the next attempt.
        clock.releaseAll()
        try await eventually("second retry wait") { clock.waitingCount == 1 && fake.attempts == 2 }

        // The daemon comes back.
        fake.script([.sendThenHang([Fixtures.sample])])
        clock.releaseAll()
        try await eventually("connected again") { store.state == .connected }

        #expect(fake.attempts == 3)
        #expect(clock.requested.count == 2)
        #expect(clock.requested.allSatisfy { $0 <= .seconds(2) }, "retry delay must be at most 2 s")
        #expect(store.sample == Fixtures.sample)
        store.stop()
    }

    @Test func requestsFiveSecondsWhenClosedAndOneSecondWhenOpen() async throws {
        let fake = FakeMonitorClient([.sendThenHang([Fixtures.sample])])
        let store = makeStore(fake)
        store.start()
        try await eventually("connected") { store.state == .connected }
        #expect(fake.requestedIntervals == [5000])

        store.setOpen(true, .popover)
        try await eventually("fast stream") { fake.requestedIntervals.count == 2 }
        #expect(fake.requestedIntervals == [5000, 1000])
        #expect(store.state == .connected, "changing rate is not a disconnect")
        #expect(store.sample != nil)

        // The dashboard opening while the popover is open changes nothing.
        store.setOpen(true, .dashboard)
        store.setOpen(false, .popover)
        #expect(store.intervalMilliseconds == 1000)

        store.setOpen(false, .dashboard)
        try await eventually("slow stream") { fake.requestedIntervals.count == 3 }
        #expect(fake.requestedIntervals == [5000, 1000, 5000])
        #expect(clock.requested.isEmpty, "a rate change must not go through the retry wait")
        store.stop()
    }

    @Test func everyNewSampleNotifiesObservers() async throws {
        let fake = FakeMonitorClient([.sendThenHang([Fixtures.sample])])
        let store = makeStore(fake)
        store.start()
        try await eventually("connected") { store.state == .connected }

        let changed = ChangeFlag()
        withObservationTracking { _ = store.sample } onChange: { changed.set() }

        // A new stream sends a different sample; the state stays connected throughout.
        let next = Fixtures.desktopUnderPressure
        fake.script([.sendThenHang([next])])
        store.setOpen(true, .popover)
        try await eventually("second sample") { store.sample == next }
        #expect(changed.isSet, "views must be told about each sample, not only the first")
        store.stop()
    }

    @Test func changingTheAddressReconnectsToTheNewDaemon() async throws {
        let fake = FakeMonitorClient([.sendThenHang([Fixtures.sample])])
        let asked = AddressLog()
        let store = MonitorStore(endpoint: .local, makeClient: { asked.add($0); return fake }, sleep: { _ in })
        store.start()
        try await eventually("connected") { store.state == .connected }

        let other = DaemonEndpoint(host: "127.0.0.1", port: 7301)
        store.setEndpoint(other)
        #expect(store.state == .connecting)
        try await eventually("connected to new address") { store.state == .connected && asked.all.last == other }
        #expect(asked.all.first == .local)
        store.stop()
    }
}

final class ChangeFlag: Sendable {
    private let flag = Mutex(false)
    func set() { flag.withLock { $0 = true } }
    var isSet: Bool { flag.withLock { $0 } }
}

final class AddressLog: Sendable {
    private let log = Mutex<[DaemonEndpoint]>([])
    func add(_ endpoint: DaemonEndpoint) { log.withLock { $0.append(endpoint) } }
    var all: [DaemonEndpoint] { log.withLock { $0 } }
}

import Synchronization
