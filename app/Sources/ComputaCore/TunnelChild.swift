import Foundation
import Synchronization
import os

/// How a tunnel's child process ended.
struct TunnelExit: Sendable, Equatable {
    var status: Int32
    var stderr: String
}

/// One long-running child (`ssh -N -L …`): started, watched until it exits, and stopped on
/// request. Its stderr is collected for the failure reason.
final class TunnelChild: Sendable {
    let pid: Int32
    private let process: Mutex<Process?>
    private let exit: Once<TunnelExit>
    private let exited: ExitFlag
    private static let logger = Logger(subsystem: "app.computa.Computa", category: "tunnel")

    /// Starts the child.
    ///
    /// - Throws: The launch error, when the executable cannot be started.
    init(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let stderr = StderrCollector()
        process.standardError = stderr.pipe
        let exit = Once<TunnelExit>()
        let exited = ExitFlag()
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            exited.set()
            stderr.whenDone { text in exit.finish(TunnelExit(status: status, stderr: text)) }
        }
        stderr.startReading()
        do {
            try process.run()
        } catch {
            stderr.closeWriter()
            Self.logger.error("could not start \(executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
        pid = process.processIdentifier
        self.process = Mutex(process)
        self.exit = exit
        self.exited = exited
    }

    var isRunning: Bool { !exited.isSet }

    /// Returns once the child has exited and its stderr is read. Call it once.
    func waitForExit() async -> TunnelExit {
        await withCheckedContinuation { exit.set($0) }
    }

    /// Sends SIGTERM now, and SIGKILL if the child is still there `grace` later.
    func terminate(grace: Duration = .milliseconds(500)) {
        guard isRunning else { return }
        kill(pid, SIGTERM)
        let pid = pid
        let seconds = Double(grace.components.seconds) + Double(grace.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [self] in
            guard isRunning else { return }
            Self.logger.error("tunnel child \(pid) ignored SIGTERM; killing it")
            kill(pid, SIGKILL)
        }
    }

    /// For quitting: SIGTERM, a short wait on this thread, then SIGKILL. Nothing scheduled for
    /// later would run once the app has exited.
    func terminateNow(wait: Duration = .milliseconds(500)) {
        guard isRunning else { return }
        kill(pid, SIGTERM)
        let deadline = ContinuousClock.now + wait
        while isRunning, ContinuousClock.now < deadline { usleep(10_000) }
        if isRunning {
            Self.logger.error("tunnel child \(self.pid) still running at quit; killing it")
            kill(pid, SIGKILL)
        }
        // Keeps the Process alive until here; Foundation reaps it.
        _ = process.withLock { $0 }
    }
}

/// Set once, from the termination handler.
private final class ExitFlag: Sendable {
    private let value = Atomic<Bool>(false)

    var isSet: Bool { value.load(ordering: .sequentiallyConsistent) }
    func set() { value.store(true, ordering: .sequentiallyConsistent) }
}

/// Collects a child's stderr until end of file on a background thread.
private final class StderrCollector: Sendable {
    let pipe = Pipe()
    private let data = Mutex(Data())
    private let done = DispatchGroup()
    /// Keeps the last part only; ssh's useful lines are its last ones.
    private static let limit = 16 * 1024

    func startReading() {
        done.enter()
        let handle = pipe.fileHandleForReading
        DispatchQueue.global().async { [self] in
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                data.withLock { stored in
                    stored.append(chunk)
                    if stored.count > Self.limit { stored.removeFirst(stored.count - Self.limit) }
                }
            }
            done.leave()
        }
    }

    /// Calls `body` with the text once the pipe reached its end, or after a second if a
    /// grandchild keeps it open.
    func whenDone(_ body: @escaping @Sendable (String) -> Void) {
        DispatchQueue.global().async { [self] in
            if done.wait(timeout: .now() + 1) == .timedOut {
                Logger(subsystem: "app.computa.Computa", category: "tunnel")
                    .error("tunnel child's stderr still open a second after it exited; using what was read")
            }
            body(String(decoding: data.withLock { $0 }, as: UTF8.self))
        }
    }

    /// For a child that never started: nothing else closes the write end.
    func closeWriter() {
        do {
            try pipe.fileHandleForWriting.close()
        } catch {
            Logger(subsystem: "app.computa.Computa", category: "tunnel").error("closing the stderr pipe failed: \(error)")
        }
    }
}

/// Loopback ports for the tunnel's local end.
enum LocalPort {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// A port nothing listens on right now: bind to port 0 on loopback, read it, close it.
    static func free() throws(Failure) -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(description: "socket() failed: \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        var address = loopback(port: 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw Failure(description: "bind() failed: \(String(cString: strerror(errno)))") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { throw Failure(description: "getsockname() failed: \(String(cString: strerror(errno)))") }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    /// True when something accepts a TCP connection on the loopback port.
    static func accepts(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = loopback(port: port)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return result == 0
    }

    private static func loopback(port: Int) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return address
    }
}
