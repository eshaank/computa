import Foundation

/// Where a tunnel to another Mac's daemon stands.
public enum TunnelState: Sendable, Equatable {
    /// Starting the tunnel; nothing to connect to yet.
    case connecting
    /// The local end accepts connections; the daemon is reached at this address.
    case connected(DaemonEndpoint)
    /// The tunnel failed, with one sentence a person can act on. It is retried by itself.
    case unreachable(String)

    public var endpoint: DaemonEndpoint? {
        if case .connected(let endpoint) = self { endpoint } else { nil }
    }
}

/// Carries a remote daemon's port to this Mac. `SSHTunnel` does it with `ssh -L`; a
/// `rex forward` tunnel can take its place once the installed Rex has that command.
@MainActor
public protocol Tunneling: AnyObject {
    var state: TunnelState { get }
    /// Called on every state change.
    var onStateChange: (@MainActor (TunnelState) -> Void)? { get set }
    /// Starts the tunnel and keeps it up until `stop`.
    func start()
    /// Ends the tunnel. The child process is signalled before this returns.
    func stop()
}

/// Makes the tunnel for a remote machine.
public typealias TunnelFactory = @MainActor (RemoteMachine) -> any Tunneling

/// Building the `ssh` command line. A pure function, so it is testable.
public enum SSHCommandLine {
    /// The arguments after the executable, for example
    /// `["-N", "-L", "127.0.0.1:50123:127.0.0.1:7300", …, "--", "morgan@m1"]`.
    ///
    /// - Throws: `.badDestination` or `.emptyDestination` for a destination that could be read
    ///   as an option, so no process is ever started with it.
    public static func arguments(for machine: RemoteMachine, localPort: Int) throws(MachineValidationError) -> [String] {
        try MachineDraft.checkDestination(machine.destination)
        var arguments = [
            "-N",
            "-L", "127.0.0.1:\(localPort):127.0.0.1:\(machine.daemonPort)",
            "-o", "ExitOnForwardFailure=yes",
            // There is no terminal to type a password into.
            "-o", "BatchMode=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            "-o", "ConnectTimeout=10",
        ]
        if let port = machine.sshPort {
            arguments += ["-p", String(port)]
        }
        return arguments + ["--", machine.destination]
    }
}

/// Turns what `ssh` printed before it exited into a sentence a person can act on.
public enum SSHFailure {
    /// - Parameters:
    ///   - stderr: Everything ssh wrote to standard error. The whole text is searched, because
    ///     ssh may print unrelated warnings first.
    ///   - status: Its exit status.
    ///   - machine: The machine it was connecting to, named in the sentence.
    public static func reason(stderr: String, status: Int32, machine: RemoteMachine) -> String {
        let text = stderr.lowercased()
        let host = machine.hostName
        func has(_ needles: String...) -> Bool { needles.contains { text.contains($0) } }
        if has("could not resolve hostname", "nodename nor servname", "name or service not known") {
            return "Cannot find \(host). Is NetBird connected?"
        }
        if has("operation timed out", "connection timed out", "timeout, server", "no route to host", "network is unreachable", "host is down") {
            return "\(host) did not answer. Is NetBird connected?"
        }
        if has("host key verification failed", "remote host identification has changed") {
            return "ssh does not trust \(host) yet. Connect once with ssh in a terminal to accept the host key."
        }
        if has("permission denied", "too many authentication failures") {
            return "\(machine.destination) refused the login. Set up an SSH key for this machine; Computa cannot type a password."
        }
        // Only ssh's own connection: "channel N: open failed: … Connection refused" is the far
        // daemon not answering, which never ends ssh.
        if text.contains("connect to host"), text.contains("connection refused") {
            return "\(host) refused the SSH connection. Turn on Remote Login on that Mac."
        }
        if has("address already in use", "cannot listen to port", "port forwarding failed") {
            return "Could not open the tunnel's local port. Computa tries another one."
        }
        let lastLine = stderr.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        if let lastLine {
            return "ssh stopped: \(lastLine)"
        }
        return "ssh stopped with status \(status) and gave no reason."
    }
}
