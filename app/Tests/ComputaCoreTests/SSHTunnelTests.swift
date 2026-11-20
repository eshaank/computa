import Foundation
import Testing

@testable import ComputaCore

/// The tunnel supervisor against stand-in `ssh` scripts. The real ssh is never run.
@MainActor
@Suite(.serialized) struct SSHTunnelTests {
    let machine = RemoteMachine(destination: "eshaan@100.64.0.5", sshPort: 2222)

    @Test func standInReceivesExactlyTheExpectedArguments() async throws {
        let ssh = try StandInSSH("exec sleep 600")
        defer { ssh.remove() }
        let tunnel = SSHTunnel(machine: machine, executable: ssh.executable.path)
        tunnel.start()
        defer { tunnel.stop() }
        try await waitUntil("the stand-in started") { ssh.pid() != nil }

        let arguments = try ssh.arguments()
        let forward = try #require(arguments.count > 2 ? arguments[2] : nil)
        let localPort = try #require(Int(forward.split(separator: ":")[1]))
        #expect(forward == "127.0.0.1:\(localPort):127.0.0.1:7300")
        #expect(localPort > 0 && localPort != 7300)
        #expect(arguments == [
            "-N", "-L", "127.0.0.1:\(localPort):127.0.0.1:7300",
            "-o", "ExitOnForwardFailure=yes", "-o", "BatchMode=yes",
            "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2", "-o", "ConnectTimeout=10",
            "-p", "2222", "--", "eshaan@100.64.0.5",
        ])
        #expect(tunnel.state == .connecting, "nothing listens on the local port, so not connected")
    }

    @Test func permissionDeniedIsUnreachableWithAReasonAndRetriedWithGrowingDelays() async throws {
        let ssh = try StandInSSH("echo 'eshaan@100.64.0.5: Permission denied (publickey).' >&2\nexit 255")
        defer { ssh.remove() }
        let clock = ManualSleep()
        let tunnel = SSHTunnel(machine: machine, executable: ssh.executable.path, sleep: { try await clock.sleep($0) })
        var states: [TunnelState] = []
        tunnel.onStateChange = { states.append($0) }
        tunnel.start()
        defer {
            tunnel.stop()
            clock.releaseAll()
        }

        try await waitUntil("first retry wait") { clock.waitingCount == 1 }
        guard case .unreachable(let reason) = tunnel.state else {
            Issue.record("expected unreachable, got \(tunnel.state)")
            return
        }
        #expect(reason == "eshaan@100.64.0.5 refused the login. Set up an SSH key for this machine; Computa cannot type a password.")
        for expectedWaits in 2...5 {
            clock.releaseFirst()
            try await waitUntil("retry wait \(expectedWaits)") { clock.waitingCount == 1 && clock.requested.count == expectedWaits }
        }
        #expect(clock.requested == [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15)])
        #expect(ssh.launchCount == 5)
        #expect(states == [.unreachable(reason)], "stays unreachable while retrying, without flickering")
    }

    @Test func stoppingKillsALongRunningStandInAndLeavesNoChild() async throws {
        let ssh = try StandInSSH("trap '' TERM HUP\nexec sleep 600")
        defer { ssh.remove() }
        let tunnel = SSHTunnel(machine: machine, executable: ssh.executable.path)
        tunnel.start()
        try await waitUntil("the stand-in started") { ssh.pid() != nil && tunnel.childPID != nil }
        let pid = try #require(ssh.pid())
        #expect(tunnel.childPID == pid)
        #expect(processExists(pid))

        tunnel.stop()
        #expect(tunnel.childPID == nil)
        // An ignored signal stays ignored across exec, so `sleep` ignores SIGTERM: this checks
        // the SIGKILL that follows.
        try await waitUntil("pid \(pid) gone", timeout: .seconds(5)) { !processExists(pid) }
        #expect(ssh.launchCount == 1, "not restarted after stop")
    }

    @Test func aHostileDestinationIsRejectedBeforeAnyProcessStarts() async throws {
        let ssh = try StandInSSH("exec sleep 600")
        defer { ssh.remove() }
        let hostile = RemoteMachine(destination: "-oProxyCommand=touch /tmp/pwned")
        let tunnel = SSHTunnel(machine: hostile, executable: ssh.executable.path)
        tunnel.start()
        defer { tunnel.stop() }
        try await waitUntil("unreachable") { tunnel.state != .connecting }
        #expect(tunnel.state == .unreachable(MachineValidationError.badDestination(hostile.destination).description))
        try await Task.sleep(for: .milliseconds(200))
        #expect(ssh.launchCount == 0)
        #expect(!FileManager.default.fileExists(atPath: ssh.pidFile.path))
    }

    @Test func aMissingSSHExecutableIsReported() async throws {
        let clock = ManualSleep()
        let tunnel = SSHTunnel(machine: machine, executable: "/nonexistent/ssh", sleep: { try await clock.sleep($0) })
        tunnel.start()
        defer {
            tunnel.stop()
            clock.releaseAll()
        }
        try await waitUntil("unreachable") { tunnel.state != .connecting }
        guard case .unreachable(let reason) = tunnel.state else { return }
        #expect(reason.hasPrefix("Could not start /nonexistent/ssh"))
    }
}
