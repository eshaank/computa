import Foundation
import Testing

@testable import ComputaCore

@Suite struct SessionMappingTests {
    /// A Claude Code pane with every field set.
    private func claudePane() -> Computa_V1_Pane {
        .with {
            $0.id = "block:a"
            $0.label = "claude"
            $0.cpuPercent = 12.0
            $0.memoryBytes = 7_500
            $0.processCount = 4
            $0.kind = .claude
            $0.program = "claude"
            $0.workingDirectory = "/Users/eshaan/Documents/computa"
            $0.processes = [
                .with {
                    $0.pid = 901
                    $0.parentPid = 900
                    $0.name = "claude"
                    $0.path = "/opt/homebrew/bin/claude"
                    $0.cpuPercent = 11.5
                    $0.memoryBytes = 7_000
                    $0.residentBytes = 9_100
                }
            ]
        }
    }

    /// A snapshot with one session of two tabs, the first holding a pane of every kind.
    private func snapshotMessage() -> Computa_V1_SessionsSnapshot {
        .with {
            $0.unixMs = 1_795_000_000_500
            $0.rex = .with { $0.reachable = true; $0.version = "0.1.0-preview.14" }
            $0.sessions = [
                .with {
                    $0.id = "session:01a1"
                    $0.label = "computa"
                    $0.cpuPercent = 14.5
                    $0.memoryBytes = 9_000
                    $0.processCount = 7
                    $0.windows = [
                        .with {
                            $0.id = "window:1"
                            $0.label = "app"
                            $0.cpuPercent = 12.5
                            $0.memoryBytes = 8_000
                            $0.processCount = 5
                            $0.panes = [
                                claudePane(),
                                .with { $0.id = "block:b"; $0.kind = .shell },
                                .with { $0.id = "block:c"; $0.kind = .program },
                                .with { $0.id = "block:d"; $0.kind = .unspecified },
                                .with { $0.id = "block:e"; $0.kind = .UNRECOGNIZED(9) },
                            ]
                        },
                        .with { $0.id = "window:2"; $0.label = "daemon" },
                    ]
                }
            ]
        }
    }

    @Test func mapsEveryFieldOfASnapshot() throws {
        let snapshot = SessionsSnapshot(snapshotMessage())
        #expect(snapshot.time == Date(timeIntervalSince1970: 1_795_000_000.5))
        #expect(snapshot.rex == RexStatus(reachable: true, problem: "", version: "0.1.0-preview.14"))

        let session = try #require(snapshot.sessions.first)
        #expect(session.id == "session:01a1")
        #expect(session.label == "computa")
        #expect(session.cpuPercent == 14.5)
        #expect(session.memoryBytes == 9_000)
        #expect(session.processCount == 7)
        #expect(session.tabs.map(\.id) == ["window:1", "window:2"])

        let tab = session.tabs[0]
        #expect(tab.label == "app")
        #expect(tab.cpuPercent == 12.5)
        #expect(tab.memoryBytes == 8_000)
        #expect(tab.processCount == 5)
        #expect(tab.panes.map(\.kind) == [.claude, .shell, .program, .unspecified, .unspecified])

        let pane = tab.panes[0]
        #expect(pane.id == "block:a")
        #expect(pane.label == "claude")
        #expect(pane.cpuPercent == 12.0)
        #expect(pane.memoryBytes == 7_500)
        #expect(pane.processCount == 4)
        #expect(pane.program == "claude")
        #expect(pane.workingDirectory == "/Users/eshaan/Documents/computa")
        #expect(pane.processes == [
            ProcessEntry(
                pid: 901, parentPid: 900, name: "claude", path: "/opt/homebrew/bin/claude",
                cpuPercent: 11.5, memoryBytes: 7_000, residentBytes: 9_100
            )
        ])
        #expect(session.paneCount == 5)
        #expect(session.claudePaneCount == 1)
    }

    @Test func mapsAnUnreachableRex() {
        let snapshot = SessionsSnapshot(Computa_V1_SessionsSnapshot.with {
            $0.unixMs = 1
            $0.rex = .with { $0.reachable = false; $0.problem = "The rex command was not found." }
        })
        #expect(snapshot.rex == RexStatus(reachable: false, problem: "The rex command was not found.", version: ""))
        #expect(snapshot.sessions.isEmpty)
    }

    @Test func aMissingRexStatusReadsAsUnreachable() {
        let snapshot = SessionsSnapshot(Computa_V1_SessionsSnapshot.with { $0.unixMs = 1 })
        #expect(!snapshot.rex.reachable)
        #expect(snapshot.rex.problem.isEmpty)
    }

    @Test func aPaneIsTitledByProgramThenLabel() {
        var pane = RexPane(
            id: "block:x", label: "build", cpuPercent: 0, memoryBytes: 0, processCount: 0, kind: .program,
            program: "cargo", workingDirectory: "", processes: []
        )
        #expect(pane.title == "cargo")
        pane.program = ""
        #expect(pane.title == "build")
        pane.label = ""
        #expect(pane.title == "pane")
        #expect(pane.badge == nil)
        pane.processes = Fixtures.sessions.sessions[0].panes[0].processes
        #expect(pane.badge == "+\(pane.processes.count - 1)")
    }
}
