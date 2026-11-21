import Foundation

/// A wait that tests can replace: they pass one they control.
public typealias SleepFunction = @Sendable (Duration) async throws -> Void

/// Waits for `duration`. Throws `CancellationError` if the task is cancelled first.
///
/// Every wait in the app goes through here. Do not call `Task.sleep(for:)` or
/// `ContinuousClock().sleep(for:)`: built for release with Swift 6.3 and run on macOS 27, both
/// aborted the app with "freed pointer was not the last allocation" when a store's wait ended
/// (first seen as the app quitting five seconds after the dashboard opened). Debug builds do not
/// show it. `Task.sleep(nanoseconds:)` is the oldest entry point and passed the same release
/// tests (`CompletedWaitTests`), as did `Task.sleep(until:clock:)`.
public func pause(for duration: Duration) async throws {
    try await Task.sleep(nanoseconds: duration.clampedNanoseconds)
}

/// Waits for real. Types take `SleepFunction?` and fall back to this in their initialiser.
let realSleep: SleepFunction = { try await pause(for: $0) }

extension Duration {
    /// This duration in whole nanoseconds: zero for a negative one, `UInt64.max` for one too
    /// long to count.
    var clampedNanoseconds: UInt64 {
        let parts = components
        guard parts.seconds >= 0, parts.attoseconds >= 0 else { return 0 }
        let (whole, tooManySeconds) = UInt64(parts.seconds).multipliedReportingOverflow(by: 1_000_000_000)
        guard !tooManySeconds else { return .max }
        let (total, tooLong) = whole.addingReportingOverflow(UInt64(parts.attoseconds / 1_000_000_000))
        return tooLong ? .max : total
    }
}
