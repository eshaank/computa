import Foundation
import Testing

@testable import ComputaCore

@Suite struct RexCommandLineTests {
    @Test func closePaneArguments() {
        let action = RexAction.closePane(sessionID: "session:01a1", paneID: "block:01a1-a")
        #expect(RexCommandLine.arguments(for: action) == [
            "do", "-s", "session:01a1", "computa_close_pane", "block_id=block:01a1-a", "--json",
        ])
    }

    @Test func openProcessViewerArguments() {
        #expect(RexCommandLine.arguments(for: .openProcessViewer(sessionID: "session:5c21")) == [
            "do", "-s", "session:5c21", "computa_open_top", "--json",
        ])
    }

    @Test func valuesWithSpacesAndEqualsStayOneArgumentEach() {
        let action = RexAction.closePane(sessionID: "my session=x", paneID: "block: a=b c")
        let arguments = RexCommandLine.arguments(for: action)
        #expect(arguments == ["do", "-s", "my session=x", "computa_close_pane", "block_id=block: a=b c", "--json"])
    }

    @Test func aHostPrefixGoesBeforeDo() {
        let arguments = RexCommandLine.arguments(
            for: .openProcessViewer(sessionID: "session:1"), prefix: RexCommandLine.hostPrefix("studio")
        )
        #expect(arguments == ["-S", "studio", "do", "-s", "session:1", "computa_open_top", "--json"])
    }
}

@Suite struct RexOutputTests {
    let close = RexAction.closePane(sessionID: "session:01a1", paneID: "block:01a1-a")
    let open = RexAction.openProcessViewer(sessionID: "session:01a1")

    func output(_ status: Int32, _ stdout: String = "", _ stderr: String = "") -> RexProcessOutput {
        RexProcessOutput(status: status, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
    }

    @Test func openTopSuccess() throws {
        let result = try RexOutput.parse(open, output(0, #"{"window_id":"window:9","program":"/opt/homebrew/bin/btop"}"#))
        #expect(result == .openedProcessViewer(program: "/opt/homebrew/bin/btop", windowID: "window:9"))
        #expect(result.summary == "Opened btop in a new tab.")
    }

    @Test func closePaneSuccess() throws {
        let result = try RexOutput.parse(close, output(0, #"{"closed":"block:01a1-a","session_id":"session:01a1"}"# + "\n"))
        #expect(result == .closedPane(paneID: "block:01a1-a", sessionID: "session:01a1"))
        #expect(result.summary == "Closed the pane.")
    }

    @Test func noActionNamedMeansNotInstalled() {
        let stderr = #"Error: no action named "computa_close_pane". Run "rex actions" to list them."# + "\n"
        #expect(throws: RexActionError.actionsNotInstalled) { try RexOutput.parse(close, output(1, "", stderr)) }
        let sentence = RexActionError.actionsNotInstalled.description
        #expect(sentence.contains("just install-rex-actions"))
        #expect(sentence.contains("rex config reload"))
    }

    @Test func anActionsOwnErrorKeepsItsText() {
        let stderr = "warning: something first\nError: computa: could not close block:01a1-a: block not found\n"
        let message = "computa: could not close block:01a1-a: block not found"
        #expect(throws: RexActionError.failed(message)) { try RexOutput.parse(close, output(1, "", stderr)) }
        #expect(RexActionError.failed(message).description == "Computa: could not close block:01a1-a: block not found.")
    }

    @Test func nonZeroExitWithEmptyStderrNamesTheStatus() {
        #expect(throws: RexActionError.failed("rex exited with status 3 and gave no reason")) {
            try RexOutput.parse(open, output(3))
        }
    }

    @Test func nonJSONStdoutIsMalformed() {
        #expect {
            try RexOutput.parse(open, output(0, "opened it"))
        } throws: { error in
            guard case RexActionError.malformedOutput(let detail) = error else { return false }
            return detail.contains("not JSON") && detail.contains("opened it")
        }
    }

    @Test func jsonWithoutTheExpectedFieldIsMalformed() {
        #expect {
            try RexOutput.parse(close, output(0, #"{"ok":true}"#))
        } throws: { error in
            guard case RexActionError.malformedOutput(let detail) = error else { return false }
            return detail.contains("closed")
        }
    }
}

@Suite struct RexLocatorTests {
    let home = "/Users/someone"
    var installed: String { home + "/" + RexLocator.installPath }

    func locate(_ setting: String = "", path: String? = "/usr/bin:/bin", executables: Set<String>) -> RexLookup {
        let environment = path.map { ["PATH": $0] } ?? [:]
        return RexLocator.locate(setting: setting, environment: environment, home: home, isExecutable: executables.contains)
    }

    @Test func theSettingWins() {
        let lookup = locate("/opt/rex/bin/rex", path: "/usr/local/bin", executables: ["/opt/rex/bin/rex", "/usr/local/bin/rex"])
        #expect(lookup == .found(path: "/opt/rex/bin/rex", source: .setting))
    }

    @Test func aSettingWithATildeIsUnderHome() {
        let lookup = locate("~/bin/rex", executables: ["/Users/someone/bin/rex"])
        #expect(lookup == .found(path: "/Users/someone/bin/rex", source: .setting))
    }

    @Test func aBadSettingIsReportedNotReplaced() {
        let lookup = locate("/nope/rex", path: "/usr/local/bin", executables: ["/usr/local/bin/rex"])
        #expect(lookup == .settingInvalid(path: "/nope/rex"))
        #expect(lookup.error == .rexNotFound("The rex command /nope/rex is not an executable file."))
    }

    @Test func pathIsSearchedInOrder() {
        let lookup = locate(path: "/a::/b:/c", executables: ["/b/rex", "/c/rex", installed])
        #expect(lookup == .found(path: "/b/rex", source: .path))
    }

    @Test func fallsBackToTheInstallLocation() {
        let lookup = locate(path: nil, executables: [installed])
        #expect(lookup == .found(path: installed, source: .installLocation))
        #expect(installed.contains("Rex Server.app"))
    }

    @Test func nothingFound() {
        let lookup = locate(executables: [])
        #expect(lookup == .notFound)
        #expect(lookup.path == nil)
        #expect(lookup.error == .rexNotFound("The rex command was not found."))
        #expect(lookup.error?.description == "The rex command was not found. Set its path in Preferences.")
    }
}

@Suite struct RexCommandSettingTests {
    func freshDefaults() -> UserDefaults {
        let name = "computa-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func emptyByDefault() {
        #expect(RexCommandSetting(defaults: freshDefaults()).path == "")
    }

    @Test func savesTrimmedAndBlankClears() {
        let setting = RexCommandSetting(defaults: freshDefaults())
        #expect(setting.save("  /opt/rex/rex ") == "/opt/rex/rex")
        #expect(setting.path == "/opt/rex/rex")
        setting.save("   ")
        #expect(setting.path == "")
    }
}
