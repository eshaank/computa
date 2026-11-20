import Foundation
import Testing

@testable import ComputaCore

/// The real runner against a stand-in `rex`: a shell script in a temporary folder whose name has
/// spaces. The script records its arguments and pid, then prints canned output. The real `rex`
/// is never run.
@Suite struct ProcessRexRunnerTests {
    let folder: URL
    var executable: URL { folder.appendingPathComponent("rex stand in") }
    var argumentsFile: URL { folder.appendingPathComponent("arguments") }
    var pidFile: URL { folder.appendingPathComponent("pid") }

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("computa rex tests \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Writes the stand-in. `body` runs after it has recorded its arguments and pid.
    func standIn(_ body: String) throws {
        let script = """
            #!/bin/sh
            echo $$ > '\(pidFile.path)'
            for argument in "$@"; do printf '%s\\n' "$argument"; done > '\(argumentsFile.path)'
            \(body)
            """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func runner(timeout: Duration = .seconds(10)) -> ProcessRexRunner {
        let path = executable.path
        return ProcessRexRunner(locate: { .found(path: path, source: .setting) }, timeout: timeout)
    }

    func recordedArguments() throws -> [String] {
        try String(contentsOf: argumentsFile, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    @Test func closePanePassesExactArgumentsAndParsesTheResult() async throws {
        try standIn(#"printf '{"closed":"block:a b=c","session_id":"session:01a1"}\n'"#)
        let action = RexAction.closePane(sessionID: "session:01a1", paneID: "block:a b=c")
        let result = try await runner().run(action)
        #expect(executable.path.contains(" "))
        #expect(try recordedArguments() == [
            "do", "-s", "session:01a1", "computa_close_pane", "block_id=block:a b=c", "--json",
        ])
        #expect(result == .closedPane(paneID: "block:a b=c", sessionID: "session:01a1"))
    }

    @Test func openTopParsesTheProgram() async throws {
        try standIn(#"echo '{"window_id":"window:7","program":"/usr/bin/top"}'"#)
        let result = try await runner().run(.openProcessViewer(sessionID: "session:5c21"))
        #expect(try recordedArguments() == ["do", "-s", "session:5c21", "computa_open_top", "--json"])
        #expect(result == .openedProcessViewer(program: "/usr/bin/top", windowID: "window:7"))
    }

    @Test func notInstalledComesBackTyped() async throws {
        try standIn(#"""
            echo 'Error: no action named "computa_close_pane". Run "rex actions" to list them.' >&2
            exit 1
            """#)
        await #expect(throws: RexActionError.actionsNotInstalled) {
            try await runner().run(.closePane(sessionID: "session:1", paneID: "block:1"))
        }
    }

    @Test func anActionErrorKeepsItsMessage() async throws {
        try standIn("echo 'Error: computa: could not close block:1: gone' >&2; exit 2")
        await #expect(throws: RexActionError.failed("computa: could not close block:1: gone")) {
            try await runner().run(.closePane(sessionID: "session:1", paneID: "block:1"))
        }
    }

    @Test func aStandInThatHangsIsKilledAtTheTimeout() async throws {
        // exec: the shell becomes `sleep`, so the recorded pid is the process that must die.
        try standIn("exec sleep 30")
        let start = ContinuousClock.now
        // A second, not less: under a loaded full test run the shell needs time to write its pid.
        await #expect(throws: RexActionError.timedOut(.seconds(1))) {
            try await runner(timeout: .seconds(1)).run(.openProcessViewer(sessionID: "session:1"))
        }
        #expect(ContinuousClock.now - start < .seconds(3))
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        var gone = false
        for _ in 0..<200 where !gone {
            gone = kill(pid, 0) == -1 && errno == ESRCH
            if !gone { try await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(gone, "stand-in pid \(pid) still exists after the timeout")
    }

    @Test func aMissingExecutableIsRexNotFound() async throws {
        let runner = ProcessRexRunner(locate: { .settingInvalid(path: "/no/such/rex") })
        await #expect(throws: RexActionError.rexNotFound("The rex command /no/such/rex is not an executable file.")) {
            try await runner.run(.openProcessViewer(sessionID: "session:1"))
        }
    }

    @Test func aFileThatCannotStartIsAFailure() async throws {
        // Executable bit set, but not a program the system can start.
        try Data([0xFF, 0x00, 0x13]).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        await #expect {
            try await runner().run(.openProcessViewer(sessionID: "session:1"))
        } throws: { error in
            guard case RexActionError.failed(let message) = error else { return false }
            return message.contains("could not start")
        }
    }
}
