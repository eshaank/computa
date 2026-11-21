import Foundation
import GRPCCore
import Synchronization

@testable import ComputaCore

/// What one `watchSystem` call on the fake does.
enum FakeStream: Sendable {
    /// Throws at once.
    case fail(RPCError)
    /// Sends the samples, then waits until cancelled.
    case sendThenHang([SystemSample])
    /// Sends the samples, then throws.
    case sendThenFail([SystemSample], RPCError)
}

/// A daemon that follows a script, one entry per connection attempt. After the script runs
/// out, the last entry repeats.
final class FakeMonitorClient: MonitorClient {
    private struct State {
        var script: [FakeStream]
        var requestedIntervals: [UInt32] = []
        var attempts = 0
    }

    private let state: Mutex<State>

    init(_ script: [FakeStream]) {
        state = Mutex(State(script: script))
    }

    var requestedIntervals: [UInt32] { state.withLock { $0.requestedIntervals } }
    var attempts: Int { state.withLock { $0.attempts } }

    /// Replaces the script from the next attempt on.
    func script(_ script: [FakeStream]) {
        state.withLock { $0.script = script }
    }

    func host() async throws -> HostInfo { Fixtures.host }

    func history(windowSeconds: UInt32, maxPoints: UInt32) async throws -> HistorySeries {
        HistorySeries(points: [], stepMilliseconds: 1000)
    }

    func watchSystem(
        intervalMilliseconds: UInt32,
        onSample: @escaping @Sendable (SystemSample) async -> Bool
    ) async throws {
        let step = state.withLock { state in
            state.requestedIntervals.append(intervalMilliseconds)
            state.attempts += 1
            return state.script.count > 1 ? state.script.removeFirst() : state.script[0]
        }
        switch step {
        case .fail(let error):
            throw error
        case .sendThenHang(let samples):
            for sample in samples where await !onSample(sample) { return }
            try await Task.sleep(for: .seconds(3600))
        case .sendThenFail(let samples, let error):
            for sample in samples where await !onSample(sample) { return }
            throw error
        }
    }
}

/// A sleep the test controls: each call is recorded and waits until the test lets it go.
final class ManualSleep: Sendable {
    private struct State {
        var requested: [Duration] = []
        var waiting: [CheckedContinuation<Void, any Error>] = []
    }

    private let state = Mutex(State())

    var requested: [Duration] { state.withLock { $0.requested } }
    var waitingCount: Int { state.withLock { $0.waiting.count } }

    func sleep(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            state.withLock {
                $0.requested.append(duration)
                $0.waiting.append(continuation)
            }
        }
    }

    /// Ends every wait in progress.
    func releaseAll() {
        let waiting = state.withLock { state in
            defer { state.waiting = [] }
            return state.waiting
        }
        waiting.forEach { $0.resume() }
    }
}

/// Waits until `condition` holds, failing after about two seconds.
@MainActor
func eventually(_ what: String, _ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<2000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    struct Timeout: Error, CustomStringConvertible { let description: String }
    throw Timeout(description: "timed out waiting for \(what)")
}

let unavailable = RPCError(code: .unavailable, message: "connection refused")
let unimplemented = RPCError(code: .unimplemented, message: "method not implemented")
