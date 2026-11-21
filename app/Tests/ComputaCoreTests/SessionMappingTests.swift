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
            $0.residentBytes = 6_400
            $0.processCount = 4
            $0.kind = .claude
            $0.program = "claude"
            $0.workingDirectory = "/Users/morgan/Documents/computa"
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
                    $0.residentBytes = 8_200
                    $0.processCount = 7
                    $0.windows = [
                        .with {
                            $0.id = "window:1"
                            $0.label = "app"
                            $0.cpuPercent = 12.5
                            $0.memoryBytes = 8_000
                            $0.residentBytes = 7_300
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
        #expect(session.residentBytes == 8_200)
        #expect(session.processCount == 7)
        #expect(session.tabs.map(\.id) == ["window:1", "window:2"])

        let tab = session.tabs[0]
        #expect(tab.label == "app")
        #expect(tab.cpuPercent == 12.5)
        #expect(tab.memoryBytes == 8_000)
        #expect(tab.residentBytes == 7_300)
        #expect(tab.processCount == 5)
        #expect(tab.panes.map(\.kind) == [.claude, .shell, .program, .unspecified, .unspecified])

        let pane = tab.panes[0]
        #expect(pane.id == "block:a")
        #expect(pane.label == "claude")
        #expect(pane.cpuPercent == 12.0)
        #expect(pane.memoryBytes == 7_500)
        #expect(pane.residentBytes == 6_400)
        #expect(pane.memory == SessionMemory(resident: 6_400, footprint: 7_500))
        #expect(pane.processCount == 4)
        #expect(pane.program == "claude")
        #expect(pane.workingDirectory == "/Users/morgan/Documents/computa")
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

/// "Mem" is resident size; an older daemon sends it as 0, and the figures fall back.
@Suite struct SessionMemoryTests {
    private func oldDaemonMessage() -> Computa_V1_SessionsSnapshot {
        .with {
            $0.rex = .with { $0.reachable = true }
            $0.sessions = [
                .with {
                    $0.id = "s"
                    $0.memoryBytes = 7_500
                    $0.windows = [
                        .with {
                            $0.id = "w"
                            $0.memoryBytes = 7_500
                            $0.panes = [
                                .with {
                                    $0.id = "p"
                                    $0.memoryBytes = 7_500
                                    $0.processes = [
                                        .with { $0.pid = 1; $0.memoryBytes = 5_000; $0.residentBytes = 3_000 },
                                        .with { $0.pid = 2; $0.memoryBytes = 2_500; $0.residentBytes = 1_000 },
                                    ]
                                },
                                // Empty, so a real zero, which does not make the tab unknown.
                                .with { $0.id = "q" },
                            ]
                        }
                    ]
                }
            ]
        }
    }

    @Test func anOlderDaemonsZeroResidentIsAddedUpFromTheProcesses() throws {
        let session = try #require(SessionsSnapshot(oldDaemonMessage()).sessions.first)
        #expect(session.residentBytes == 0)
        #expect(session.tabs[0].panes[0].memory == SessionMemory(resident: 4_000, footprint: 7_500))
        #expect(session.tabs[0].panes[1].memory == SessionMemory(resident: 0, footprint: 0))
        #expect(session.tabs[0].memory == SessionMemory(resident: 4_000, footprint: 7_500))
        #expect(session.memory == SessionMemory(resident: 4_000, footprint: 7_500))
        #expect(!session.memory.isFootprintOnly)
    }

    @Test func unknownResidentFallsBackToTheFootprintAndSaysSo() throws {
        let session = try #require(Fixtures.sessionsOldDaemon.sessions.first)
        for memory in [session.memory, session.tabs[0].memory, session.tabs[0].panes[0].memory] {
            #expect(memory.resident == nil)
            #expect(memory.isFootprintOnly)
            #expect(memory.shownBytes == memory.footprint)
            #expect(memory.shownBytes > 0)
        }
    }

    @Test func aReportedResidentWinsOverTheProcesses() {
        let pane = RexPane(
            id: "p", label: "", cpuPercent: 0, memoryBytes: 900, residentBytes: 600, processCount: 1, kind: .shell,
            program: "zsh", workingDirectory: "",
            processes: [ProcessEntry(pid: 1, parentPid: 0, name: "zsh", path: "", cpuPercent: 0, memoryBytes: 900, residentBytes: 10)]
        )
        #expect(pane.memory == SessionMemory(resident: 600, footprint: 900))
    }

    @Test func aTotalIsResidentOnlyWhenEveryPartIs() {
        let known = SessionMemory(resident: 100, footprint: 300)
        let unknown = SessionMemory(resident: nil, footprint: 50)
        #expect(SessionMemory.total([known, known]) == SessionMemory(resident: 200, footprint: 600))
        #expect(SessionMemory.total([known, unknown]) == SessionMemory(resident: nil, footprint: 350))
        #expect(SessionMemory.total([]) == SessionMemory(resident: 0, footprint: 0))
    }

    @Test func theFixturesResidentSizesDifferFromTheirFootprints() {
        for session in Fixtures.sessions.sessions {
            #expect(session.memory.resident != nil)
            #expect(session.memory.shownBytes < session.memory.footprint)
        }
    }
}
