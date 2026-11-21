import Foundation
import Testing

@testable import ComputaCore

@Suite struct SSHCommandTests {
    let m1 = RemoteMachine(destination: "morgan@100.64.0.5")

    @Test func argumentsWithoutAPort() throws {
        #expect(try SSHCommandLine.arguments(for: m1, localPort: 50123) == [
            "-N", "-L", "127.0.0.1:50123:127.0.0.1:7300",
            "-o", "ExitOnForwardFailure=yes", "-o", "BatchMode=yes",
            "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2", "-o", "ConnectTimeout=10",
            "--", "morgan@100.64.0.5",
        ])
    }

    @Test func argumentsWithAPortAndAnotherDaemonPort() throws {
        let machine = RemoteMachine(destination: "m1", sshPort: 2222, daemonPort: 7400)
        #expect(try SSHCommandLine.arguments(for: machine, localPort: 6000) == [
            "-N", "-L", "127.0.0.1:6000:127.0.0.1:7400",
            "-o", "ExitOnForwardFailure=yes", "-o", "BatchMode=yes",
            "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2", "-o", "ConnectTimeout=10",
            "-p", "2222", "--", "m1",
        ])
    }

    @Test(arguments: ["-oProxyCommand=touch /tmp/x", "me@m1 -p 1", " me@m1", "", "me@"])
    func hostileDestinationsAreRejected(_ destination: String) {
        #expect(throws: MachineValidationError.self) {
            try SSHCommandLine.arguments(for: RemoteMachine(destination: destination), localPort: 6000)
        }
    }

    @Test(arguments: [
        ("ssh: Could not resolve hostname m1: nodename nor servname provided, or not known", "Cannot find 100.64.0.5. Is NetBird connected?"),
        ("ssh: connect to host 100.64.0.5 port 22: Operation timed out", "100.64.0.5 did not answer. Is NetBird connected?"),
        ("Timeout, server 100.64.0.5 not responding.", "100.64.0.5 did not answer. Is NetBird connected?"),
        ("ssh: connect to host 100.64.0.5 port 22: No route to host", "100.64.0.5 did not answer. Is NetBird connected?"),
        (
            "morgan@100.64.0.5: Permission denied (publickey,password,keyboard-interactive).",
            "morgan@100.64.0.5 refused the login. Set up an SSH key for this machine; Computa cannot type a password."
        ),
        (
            "No ED25519 host key is known for 100.64.0.5 and you have requested strict checking.\nHost key verification failed.",
            "ssh does not trust 100.64.0.5 yet. Connect once with ssh in a terminal to accept the host key."
        ),
        (
            "ssh: connect to host 100.64.0.5 port 22: Connection refused",
            "100.64.0.5 refused the SSH connection. Turn on Remote Login on that Mac."
        ),
        (
            "bind [127.0.0.1]:50123: Address already in use\nchannel_setup_fwd_listener_tcpip: cannot listen to port: 50123\nCould not request local forwarding.",
            "Could not open the tunnel's local port. Computa tries another one."
        ),
        ("Warning: Permanently added '100.64.0.5' (ED25519) to the list of known hosts.\nkex_exchange_identification: read: Connection reset by peer\n", "ssh stopped: kex_exchange_identification: read: Connection reset by peer"),
        ("", "ssh stopped with status 255 and gave no reason."),
    ])
    func stderrBecomesAReason(_ stderr: String, _ reason: String) {
        #expect(SSHFailure.reason(stderr: stderr, status: 255, machine: m1) == reason)
    }

    @Test func aRefusedChannelIsNotMistakenForRemoteLoginBeingOff() {
        let stderr = "channel 2: open failed: connect failed: Connection refused\nTimeout, server 100.64.0.5 not responding."
        #expect(SSHFailure.reason(stderr: stderr, status: 255, machine: m1).contains("NetBird"))
    }

    @Test func reasonIsFoundBehindUnrelatedWarnings() {
        let stderr = "** WARNING: connection is not using a post-quantum key exchange algorithm.\nmorgan@100.64.0.5: Permission denied (publickey)."
        #expect(SSHFailure.reason(stderr: stderr, status: 255, machine: m1).contains("SSH key"))
    }

    @Test func rexActionsOnARemoteMachineGoThroughItsHostLabel() throws {
        var list = MachineList()
        let labelled = try list.add(MachineDraft(name: "M1", destination: "me@m1", rexHost: "m1"))
        let unlabelled = try list.add(MachineDraft(name: "Studio", destination: "me@studio"))
        let action = RexAction.closePane(sessionID: "session:9", paneID: "block:3")

        #expect(labelled.rexTarget == .host("m1"))
        let prefix = try #require(labelled.rexTarget.prefix)
        #expect(RexCommandLine.arguments(for: action, prefix: prefix) == [
            "-S", "m1", "do", "-s", "session:9", "computa_close_pane", "block_id=block:3", "--json",
        ])
        #expect(unlabelled.rexTarget == .unavailable)
        #expect(unlabelled.rexTarget.prefix == nil)
        #expect(list.machines[0].rexTarget.prefix == [])
    }
}
