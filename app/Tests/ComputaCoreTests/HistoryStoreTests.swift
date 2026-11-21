import Foundation
import Testing

@testable import ComputaCore

@MainActor
@Suite struct HistoryStoreTests {
    let clock = ManualSleep()

    func makeStore(_ fake: FakeMonitorClient) -> HistoryStore {
        let clock = clock
        return HistoryStore(endpoint: .local, makeClient: { _ in fake }, sleep: { try await clock.sleep($0) })
    }

    @Test func fetchesNothingUntilOpened() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = makeStore(fake)
        try await pause(for: .milliseconds(20))
        #expect(fake.historyRequests.isEmpty)
        #expect(store.series == nil)
        #expect(!store.isRunning)
    }

    @Test func fetchesOnOpenThenAgainOnEachTick() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let first = Fixtures.history(count: 2)
        let second = Fixtures.history(count: 5)
        fake.scriptHistory([.success(first), .success(second)])
        let store = makeStore(fake)

        store.setOpen(true)
        try await eventually("first fetch and wait") { store.series == first && clock.waitingCount == 1 }
        #expect(fake.historyRequests == [.init(windowSeconds: 900, maxPoints: 90)])
        #expect(clock.requested == [HistoryStore.refreshInterval])
        #expect(HistoryStore.refreshInterval == .seconds(5))

        clock.releaseAll()
        try await eventually("second fetch") { store.series == second && clock.waitingCount == 1 }
        #expect(fake.historyRequests.count == 2)
        #expect(store.fetchCount == 2)

        store.setOpen(false)
        clock.releaseAll()
        try await pause(for: .milliseconds(20))
        #expect(fake.historyRequests.count == 2, "no fetch after closing")
        #expect(store.series == nil, "closing drops the history")
        #expect(!store.isRunning)
        #expect(clock.waitingCount == 0)
    }

    @Test func changingTheRangeDropsTheOldSeriesAndFetchesTheNewWindow() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        let store = makeStore(fake)
        store.setOpen(true)
        try await eventually("first fetch") { store.series != nil && clock.waitingCount == 1 }

        fake.scriptHistory([.failure(unavailable)])
        store.setRange(.oneHour)
        #expect(store.series == nil, "a 15-minute chart must not show under a 1-hour label")
        try await eventually("refetch") { fake.historyRequests.count == 2 }
        #expect(fake.historyRequests.last == .init(windowSeconds: 3600, maxPoints: 90))
        store.setOpen(false)
        clock.releaseAll()
    }

    @Test func aFailureClearsTheSeriesAndAnUnimplementedCallNeedsAnUpdate() async throws {
        let fake = FakeMonitorClient([.fail(unavailable)])
        fake.scriptHistory([.success(Fixtures.history(count: 3)), .failure(unimplemented)])
        let store = makeStore(fake)
        store.setOpen(true)
        try await eventually("first fetch") { store.series != nil && clock.waitingCount == 1 }

        clock.releaseAll()
        try await eventually("failure") { store.problem != nil }
        #expect(store.problem?.kind == .unsupported)
        #expect(store.series == nil)
        #expect(store.isRunning, "keeps trying on the timer")
        store.setOpen(false)
        clock.releaseAll()
    }
}
