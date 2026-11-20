/// A wait that tests can replace: they pass one they control.
public typealias SleepFunction = @Sendable (Duration) async throws -> Void

/// Waits for real.
///
/// Types take `SleepFunction?` and fall back to this inside their initialiser. A default
/// argument of `{ try await Task.sleep(for: $0) }` on a main-actor initialiser, used from
/// another module, crashed with "freed pointer was not the last allocation" as soon as the wait
/// was cancelled (seen with Swift 6 on macOS 27: closing the dashboard during a history wait).
let realSleep: SleepFunction = { try await Task.sleep(for: $0) }
