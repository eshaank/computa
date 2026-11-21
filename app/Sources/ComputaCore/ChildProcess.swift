import Foundation
import Synchronization
import os

/// Runs one child process with a time limit, capturing stdout and stderr. Nothing here blocks
/// the caller's thread: pipes are read on their own threads and the exit arrives by callback.
enum ChildProcess {
    private enum Ending: Sendable {
        case exited(RexProcessOutput)
        case timedOut
        case launchFailed(String)
    }

    private static let logger = Logger(subsystem: "app.computa.Computa", category: "rex")

    /// - Throws: `.timedOut` when the child outlives `timeout` (it is then stopped), or
    ///   `.failed` when it cannot be started.
    static func run(
        executable: String, arguments: [String], timeout: Duration
    ) async throws(RexActionError) -> RexProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let capture = Capture()
        process.standardOutput = capture.stdout
        process.standardError = capture.stderr
        let once = Once<Ending>()
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            capture.whenRead { out, err in
                once.finish(.exited(RexProcessOutput(status: status, stdout: out, stderr: err)))
            }
        }
        let ending: Ending = await withCheckedContinuation { continuation in
            once.set(continuation)
            // Readers start first, so the exit callback always waits for them.
            capture.startReading()
            do {
                try process.run()
            } catch {
                capture.closeWriters()
                once.finish(.launchFailed("could not start \(executable): \(error.localizedDescription)"))
                return
            }
            let pid = process.processIdentifier
            Task.detached {
                do {
                    try await pause(for: timeout)
                } catch {
                    logger.error("rex timeout wait for pid \(pid) ended early: \(error)")
                }
                if once.finish(.timedOut) { stop(pid: pid) }
            }
        }
        switch ending {
        case .exited(let output): return output
        case .timedOut: throw .timedOut(timeout)
        case .launchFailed(let message): throw .failed(message)
        }
    }

    /// SIGTERM, then SIGKILL if it is still there half a second later.
    private static func stop(pid: Int32) {
        logger.error("rex (pid \(pid)) timed out; stopping it")
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }
}

/// Resumes a continuation exactly once: the process exiting and the timeout race. Also used by
/// `TunnelChild`.
final class Once<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, Never>?
        var pending: Value?
        var done = false
    }

    private let state = Mutex(State())

    func set(_ continuation: CheckedContinuation<Value, Never>) {
        let pending: Value? = state.withLock { state in
            if let pending = state.pending { return pending }
            state.continuation = continuation
            return nil
        }
        if let pending { continuation.resume(returning: pending) }
    }

    /// - Returns: True if this call ended the wait.
    @discardableResult
    func finish(_ value: Value) -> Bool {
        let (won, continuation): (Bool, CheckedContinuation<Value, Never>?) = state.withLock { state in
            guard !state.done else { return (false, nil) }
            state.done = true
            if state.continuation == nil { state.pending = value }
            defer { state.continuation = nil }
            return (true, state.continuation)
        }
        continuation?.resume(returning: value)
        return won
    }
}

/// Reads a child's stdout and stderr to the end on background threads, so a child that prints a
/// lot never blocks on a full pipe.
private final class Capture: Sendable {
    let stdout = Pipe()
    let stderr = Pipe()
    private let group = DispatchGroup()
    private let output = Mutex<(Data, Data)>((Data(), Data()))

    func startReading() {
        read(stdout) { data in self.output.withLock { $0.0 = data } }
        read(stderr) { data in self.output.withLock { $0.1 = data } }
    }

    /// Calls `body` once both pipes reached their end.
    func whenRead(_ body: @escaping @Sendable (Data, Data) -> Void) {
        group.notify(queue: .global()) { [self] in
            let (out, err) = output.withLock { $0 }
            body(out, err)
        }
    }

    /// For a child that never started: nothing else will close the write ends.
    func closeWriters() {
        for pipe in [stdout, stderr] {
            do {
                try pipe.fileHandleForWriting.close()
            } catch {
                Logger(subsystem: "app.computa.Computa", category: "rex").error("closing a rex pipe failed: \(error)")
            }
        }
    }

    private func read(_ pipe: Pipe, into store: @escaping @Sendable (Data) -> Void) {
        group.enter()
        DispatchQueue.global().async { [group] in
            let handle = pipe.fileHandleForReading
            do {
                store(try handle.readToEnd() ?? Data())
            } catch {
                Logger(subsystem: "app.computa.Computa", category: "rex").error("reading rex output failed: \(error)")
            }
            group.leave()
        }
    }
}
