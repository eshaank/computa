import Foundation
import GRPCCore
import Synchronization
import Testing

@testable import ComputaCore

@MainActor
@Suite struct RemoteIconCacheTests {
    let fake = FakeMonitorClient([.fail(unavailable)])
    let endpoint = DaemonEndpoint(host: "127.0.0.1", port: 6001)
    let png = Data([0x89, 0x50, 0x4E, 0x47])

    let clock = TestClock()

    func cache() -> RemoteIconCache {
        let fake = fake
        let clock = clock
        return RemoteIconCache(makeClient: { _ in fake }, now: { clock.now })
    }

    func key(_ path: String, on machine: String = "m1") -> RemoteIconCache.Key {
        RemoteIconCache.Key(machineID: machine, bundlePath: path)
    }

    @Test func fetchesOnceAndThenAnswersFromTheCache() async {
        fake.scriptIcon("/Applications/Safari.app", .success(png))
        let cache = cache()
        #expect(cache.entry(for: key("/Applications/Safari.app"), endpoint: endpoint) == nil, "not known yet")
        #expect(await cache.load(key("/Applications/Safari.app"), endpoint: endpoint) == .png(png))
        #expect(cache.entry(for: key("/Applications/Safari.app"), endpoint: endpoint) == .png(png))
        #expect(fake.iconRequests == ["/Applications/Safari.app"])
    }

    @Test func concurrentRequestsForTheSameIconAreOne() async {
        fake.scriptIcon("/Applications/Mail.app", .success(png))
        let cache = cache()
        _ = cache.entry(for: key("/Applications/Mail.app"), endpoint: endpoint)
        _ = cache.entry(for: key("/Applications/Mail.app"), endpoint: endpoint)
        async let first = cache.load(key("/Applications/Mail.app"), endpoint: endpoint)
        async let second = cache.load(key("/Applications/Mail.app"), endpoint: endpoint)
        let results = await [first, second]
        #expect(results == [.png(png), .png(png)])
        #expect(fake.iconRequests.count == 1)
        #expect(cache.requestCount == 1)
    }

    @Test func noIconIsCachedToo() async {
        let cache = cache()
        #expect(await cache.load(key("/Applications/Plain.app"), endpoint: endpoint) == .noIcon)
        _ = cache.entry(for: key("/Applications/Plain.app"), endpoint: endpoint)
        #expect(fake.iconRequests.count == 1)
    }

    @Test func eachMachineHasItsOwnCache() async {
        fake.scriptIcon("/Applications/Safari.app", .success(png))
        let cache = cache()
        _ = await cache.load(key("/Applications/Safari.app", on: "m1"), endpoint: endpoint)
        _ = await cache.load(key("/Applications/Safari.app", on: "studio"), endpoint: endpoint)
        #expect(fake.iconRequests.count == 2)
        #expect(cache.entries.count == 2)
    }

    @Test func failuresAreAskedAgainOnlyAfterTheRetryDelay() async {
        fake.scriptIcon("/Applications/Broken.app", .failure(unavailable))
        let cache = cache()
        #expect(await cache.load(key("/Applications/Broken.app"), endpoint: endpoint) == nil)
        #expect(cache.entries.isEmpty, "a failure is not kept as an icon")
        _ = await cache.load(key("/Applications/Broken.app"), endpoint: endpoint)
        #expect(fake.iconRequests.count == 1, "not asked again on the next redraw")
        clock.advance(by: RemoteIconCache.retryAfter + .seconds(1))
        _ = await cache.load(key("/Applications/Broken.app"), endpoint: endpoint)
        #expect(fake.iconRequests.count == 2, "asked again later")
        #expect(cache.entry(for: key("/Applications/Other.app"), endpoint: nil) == nil)
        #expect(fake.iconRequests.count == 2, "no request while the tunnel is down")
    }
}

/// A clock the test moves by hand.
final class TestClock: Sendable {
    private let instant = Mutex(ContinuousClock.now)

    var now: ContinuousClock.Instant { instant.withLock { $0 } }

    func advance(by duration: Duration) {
        instant.withLock { $0 = $0.advanced(by: duration) }
    }
}
