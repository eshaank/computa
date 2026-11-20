import Foundation

@testable import ComputaCore

/// A stand-in `ssh`: a shell script in a temporary folder whose name has spaces. It records its
/// pid and arguments, appends its pid to a launch log, then runs `body`. Bodies that keep
/// running must `exec` their command, so the pid recorded is the process the tunnel stops.
struct StandInSSH {
    let folder: URL
    var executable: URL { folder.appendingPathComponent("ssh stand in") }
    var argumentsFile: URL { folder.appendingPathComponent("arguments") }
    var pidFile: URL { folder.appendingPathComponent("pid") }
    var launchesFile: URL { folder.appendingPathComponent("launches") }

    init(_ body: String) throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("computa ssh tests \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = """
            #!/bin/sh
            echo $$ >> '\(launchesFile.path)'
            for argument in "$@"; do printf '%s\\n' "$argument"; done > '\(argumentsFile.path)'
            echo $$ > '\(pidFile.path)'
            \(body)
            """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func arguments() throws -> [String] {
        try String(contentsOf: argumentsFile, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    /// The pid written by the latest launch, once it is there.
    func pid() -> Int32? {
        (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    var launchCount: Int {
        ((try? String(contentsOf: launchesFile, encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// True while a process with this pid exists (a zombie counts until it is reaped).
func processExists(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
}

/// Waits until `condition` holds, failing after `timeout`.
@MainActor
func waitUntil(_ what: String, timeout: Duration = .seconds(10), _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    if condition() { return }
    struct Timeout: Error, CustomStringConvertible { let description: String }
    throw Timeout(description: "timed out after \(timeout) waiting for \(what)")
}

/// The first python3 found, for the forwarding stand-in.
let python3Path: String? = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
    .first { FileManager.default.isExecutableFile(atPath: $0) }

/// A forwarder in Python: listens on the `-L` argument's local port and carries every
/// connection to the port after it on 127.0.0.1, like `ssh -L` does to the far side.
let forwarderScript = #"""
    import socket, sys, threading
    spec = sys.argv[sys.argv.index("-L") + 1].split(":")
    local_port, remote_port = int(spec[1]), int(spec[3])
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", local_port))
    server.listen(16)
    def pipe(a, b):
        try:
            while True:
                data = a.recv(65536)
                if not data:
                    break
                b.sendall(data)
        except OSError:
            pass
        finally:
            for s in (a, b):
                try:
                    s.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
    def handle(client):
        try:
            upstream = socket.create_connection(("127.0.0.1", remote_port))
        except OSError:
            client.close()
            return
        threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
        threading.Thread(target=pipe, args=(upstream, client), daemon=True).start()
    while True:
        client, _ = server.accept()
        threading.Thread(target=handle, args=(client,), daemon=True).start()
    """#

/// The phase 6 daemon, started on a free port for one test and stopped by pid.
final class DaemonUnderTest {
    static let binary = "/tmp/claude-501/bin/computad-p6"
    let process = Process()
    let port: Int

    init() throws {
        port = try LocalPort.free()
        process.executableURL = URL(fileURLWithPath: Self.binary)
        process.environment = ProcessInfo.processInfo.environment.merging(["COMPUTAD_LISTEN": "127.0.0.1:\(port)"]) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    var pid: Int32 { process.processIdentifier }

    /// Waits until the daemon accepts connections.
    @MainActor
    func waitUntilListening() async throws {
        let port = port
        try await waitUntil("computad-p6 listening on \(port)") { LocalPort.accepts(port) }
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }
}
