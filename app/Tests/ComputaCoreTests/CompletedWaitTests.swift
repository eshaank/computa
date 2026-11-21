import Foundation
import Testing

@testable import ComputaCore

/// Stores built with their real wait, left alone until the wait finishes by itself. The app
/// built for release aborted here ("freed pointer was not the last allocation") the first time
/// the dashboard's five-second history wait ended, while `pause(for:)` did the waiting.
/// A debug build never showed it, so `just test-release` runs these as a release build.
@MainActor
@Suite struct CompletedWaitTests {
    @Test func theHistoryStoreFetchesAgainAfterItsWait() async throws {
        let fake = FakeMonitorClient([])
        let store = HistoryStore(endpoint: .local, makeClient: { _ in fake })
        store.setOpen(true)
        try await eventually("first fetch") { store.fetchCount == 1 }
        try await waitUntil("second fetch", within: HistoryStore.refreshInterval * 3) { store.fetchCount >= 2 }
        store.setOpen(false)
        #expect(fake.historyRequests.count >= 2)
    }

    @Test func theMonitorStoreConnectsAgainAfterItsRetryWait() async throws {
        let fake = FakeMonitorClient([.fail(unavailable), .fail(unavailable)])
        let store = MonitorStore(endpoint: .local, makeClient: { _ in fake })
        store.start()
        try await waitUntil("second attempt", within: .seconds(30)) { fake.attempts >= 2 }
        store.stop()
    }

    /// The real gRPC client against a port nothing listens on, long enough for several retries.
    /// The gRPC libraries wait with `Task.sleep(for:)` themselves when a connection fails.
    @Test func theRealClientKeepsRetryingADaemonThatIsNotRunning() async throws {
        let nothingListens = DaemonEndpoint(host: "127.0.0.1", port: 1)
        let monitor = MonitorStore(endpoint: nothingListens)
        let history = HistoryStore(endpoint: nothingListens)
        monitor.start()
        history.setOpen(true)
        try await pause(for: HistoryStore.refreshInterval * 2 + .seconds(2))
        #expect(history.fetchCount >= 2)
        #expect(history.problem != nil)
        #expect(monitor.state != .connecting)
        history.setOpen(false)
        monitor.stop()
        // Time for the cancelled calls and their connections to finish closing.
        try await pause(for: .seconds(1))
    }

    /// A debug test run cannot see the abort, so this keeps the call out of the app and its tests.
    @Test(arguments: ["Sources", "Tests"])
    func noFileUsesTheWaitThatAbortsInReleaseBuilds(folder: String) throws {
        let thisFile = URL(filePath: #filePath)
        let root = thisFile
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: folder)
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        var checked = 0
        for case let file as URL in files where file.pathExtension == "swift" {
            // This file names the call in order to look for it.
            guard file.lastPathComponent != thisFile.lastPathComponent else { continue }
            checked += 1
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), code.contains(".sleep(for:") else { continue }
                offenders.append("\(file.lastPathComponent):\(index + 1)")
            }
        }
        #expect(checked > 20, "the \(folder) folder was not found")
        #expect(offenders.isEmpty, "use pause(for:) instead of sleep(for:) in \(offenders)")
    }

    @Test func aDurationBecomesWholeNanoseconds() {
        #expect(Duration.seconds(5).clampedNanoseconds == 5_000_000_000)
        #expect(Duration.milliseconds(250).clampedNanoseconds == 250_000_000)
        #expect(Duration.zero.clampedNanoseconds == 0)
        #expect(Duration.seconds(-3).clampedNanoseconds == 0)
        #expect(Duration.seconds(Int64.max).clampedNanoseconds == .max)
    }
}

/// Like `eventually`, for waits measured in seconds.
@MainActor
func waitUntil(_ what: String, within limit: Duration, _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + limit
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    struct Timeout: Error, CustomStringConvertible { let description: String }
    throw Timeout(description: "timed out waiting for \(what)")
}
