import Foundation
import os

/// A tunnel made with `ssh -N -L`: one `ssh` child, restarted with a growing delay whenever it
/// exits, until `stop`.
///
/// "Connected" means the local end accepts a TCP connection, which ssh only allows after it
/// has logged in. The reason for `unreachable` comes from what ssh printed.
@MainActor
public final class SSHTunnel: Tunneling {
    public static let defaultExecutable = "/usr/bin/ssh"
    /// The first wait before restarting ssh; it doubles after each failure.
    public static let firstRetryDelay: Duration = .seconds(1)
    /// The longest wait between restarts.
    public static let maxRetryDelay: Duration = .seconds(15)

    public let machine: RemoteMachine
    public private(set) var state: TunnelState = .connecting {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    public var onStateChange: (@MainActor (TunnelState) -> Void)?
    /// The running `ssh`'s pid, if one runs. For tests and logs.
    public var childPID: Int32? { child?.pid }

    private let executable: String
    private let sleep: @Sendable (Duration) async throws -> Void
    private let probeInterval: Duration
    private var loop: Task<Void, Never>?
    private var child: TunnelChild?
    private var generation = 0
    private let logger = Logger(subsystem: "app.computa.Computa", category: "tunnel")

    /// - Parameters:
    ///   - executable: The `ssh` to run. Tests pass a stand-in script.
    ///   - sleep: Waits between restarts. Tests pass one they control.
    ///   - probeInterval: Time between checks that the local end accepts connections.
    public init(
        machine: RemoteMachine, executable: String = defaultExecutable,
        sleep: SleepFunction? = nil,
        probeInterval: Duration = .milliseconds(200)
    ) {
        self.machine = machine
        self.executable = executable
        self.sleep = sleep ?? realSleep
        self.probeInterval = probeInterval
    }

    public func start() {
        guard loop == nil else { return }
        generation += 1
        let current = generation
        logger.info("tunnel to \(self.machine.destination, privacy: .public) starting")
        loop = Task { [weak self] in await self?.supervise(generation: current) }
    }

    /// Ends the loop and sends SIGTERM to ssh at once (SIGKILL half a second later if needed).
    public func stop() {
        generation += 1
        loop?.cancel()
        loop = nil
        if let child {
            logger.info("tunnel to \(self.machine.destination, privacy: .public) stopping; ssh pid \(child.pid)")
            child.terminate()
        }
        child = nil
    }

    /// Like `stop`, but waits briefly for ssh to exit. For quitting the app.
    public func stopNow() {
        let running = child
        stop()
        running?.terminateNow()
    }

    // MARK: - The loop

    private func supervise(generation current: Int) async {
        do {
            try MachineDraft.checkDestination(machine.destination)
        } catch {
            logger.error("tunnel not started, unsafe destination: \(error.description, privacy: .public)")
            state = .unreachable(error.description)
            return
        }
        var delay = Self.firstRetryDelay
        while isCurrent(current) {
            let (connected, reason) = await attempt(generation: current)
            guard isCurrent(current) else { return }
            if connected { delay = Self.firstRetryDelay }
            logger.error("tunnel to \(self.machine.destination, privacy: .public) down: \(reason, privacy: .public); retrying in \(delay)")
            // Stays unreachable through the retries, so the reason does not flicker away.
            state = .unreachable(reason)
            do {
                try await sleep(delay)
            } catch {
                logger.debug("tunnel retry wait ended: \(error)")
                return
            }
            delay = min(delay * 2, Self.maxRetryDelay)
        }
    }

    /// Runs ssh once, until it exits.
    ///
    /// - Returns: Whether the tunnel was up at some point, and why it ended.
    private func attempt(generation current: Int) async -> (Bool, String) {
        let port: Int
        let child: TunnelChild
        do {
            port = try LocalPort.free()
        } catch {
            logger.error("no free local port: \(error.description, privacy: .public)")
            return (false, "Could not pick a local port for the tunnel: \(error.description).")
        }
        do {
            let arguments = try SSHCommandLine.arguments(for: machine, localPort: port)
            child = try TunnelChild(executable: executable, arguments: arguments)
        } catch let error as MachineValidationError {
            return (false, error.description)
        } catch {
            return (false, "Could not start \(executable): \(error.localizedDescription)")
        }
        guard isCurrent(current) else {
            child.terminate()
            return (false, "Stopped.")
        }
        self.child = child
        logger.info("ssh pid \(child.pid) to \(self.machine.destination, privacy: .public), local port \(port)")
        if await waitUntilListening(child, port: port, generation: current) {
            logger.info("tunnel to \(self.machine.destination, privacy: .public) up on 127.0.0.1:\(port)")
            state = .connected(DaemonEndpoint(host: "127.0.0.1", port: port))
        }
        let connected = state.endpoint?.port == port
        let exit = await child.waitForExit()
        if self.child === child { self.child = nil }
        logger.error("ssh pid \(child.pid) exited with status \(exit.status): \(exit.stderr, privacy: .public)")
        return (connected, SSHFailure.reason(stderr: exit.stderr, status: exit.status, machine: machine))
    }

    private func waitUntilListening(_ child: TunnelChild, port: Int, generation current: Int) async -> Bool {
        while child.isRunning, isCurrent(current) {
            if await Self.probe(port) { return child.isRunning && isCurrent(current) }
            do {
                try await pause(for: probeInterval)
            } catch {
                return false
            }
        }
        return false
    }

    /// Off the main actor: a connect, even on loopback, is a system call.
    nonisolated private static func probe(_ port: Int) async -> Bool {
        LocalPort.accepts(port)
    }

    private func isCurrent(_ current: Int) -> Bool {
        current == generation && !Task.isCancelled
    }
}
