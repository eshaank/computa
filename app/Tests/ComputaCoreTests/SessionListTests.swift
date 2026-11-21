import Foundation
import Testing

@testable import ComputaCore

private func process(_ name: String, pid: Int32, cpu: Double, memory: UInt64) -> ProcessEntry {
    ProcessEntry(pid: pid, parentPid: 1, name: name, path: "", cpuPercent: cpu, memoryBytes: memory, residentBytes: 0)
}

/// `memory` is the footprint; the resident size is `resident`, else the same as the footprint.
private func pane(
    _ id: String, _ program: String, cpu: Double, memory: UInt64, resident: UInt64? = nil, kind: PaneKind = .program,
    processes: [ProcessEntry] = []
) -> RexPane {
    RexPane(
        id: id, label: "", cpuPercent: cpu, memoryBytes: memory, residentBytes: resident ?? memory,
        processCount: processes.count, kind: kind, program: program, workingDirectory: "", processes: processes
    )
}

private func session(_ id: String, _ label: String, cpu: Double, memory: UInt64, tabs: [[RexPane]]) -> RexSession {
    RexSession(
        id: id, label: label, cpuPercent: cpu, memoryBytes: memory, processCount: 0,
        tabs: tabs.enumerated().map { index, panes in
            RexTab(id: "\(id)/\(index)", label: "tab \(index)", cpuPercent: 0, memoryBytes: 0, processCount: 0, panes: panes)
        }
    )
}

@Suite struct SessionSortingTests {
    let sessions = [
        session("s:3", "beta", cpu: 5, memory: 100, tabs: [[]]),
        session("s:1", "Alpha", cpu: 50, memory: 100, tabs: [[]]),
        session("s:2", "alpha", cpu: 1, memory: 900, tabs: [[]]),
        session("s:0", "alpha", cpu: 5, memory: 100, tabs: [[]]),
    ]

    @Test func sessionsByMemoryWithTiesByLabelThenId() {
        // 900 first; the three at 100 by label ignoring case ("Alpha" = "alpha" → by id), then "beta".
        #expect(SessionList.sorted(sessions, by: .memory).map(\.id) == ["s:2", "s:0", "s:1", "s:3"])
    }

    @Test func sessionsByCpu() {
        // s:3 and s:0 tie at 5: "alpha" before "beta".
        #expect(SessionList.sorted(sessions, by: .cpu).map(\.id) == ["s:1", "s:0", "s:3", "s:2"])
    }

    @Test func panesAndProcessesSortInsideEachTabWhileTabsKeepRexOrder() {
        let tree = session("s", "s", cpu: 0, memory: 0, tabs: [
            [
                pane("p:b", "zsh", cpu: 9, memory: 10),
                pane("p:a", "zsh", cpu: 1, memory: 10),
                pane("p:c", "claude", cpu: 2, memory: 500, kind: .claude, processes: [
                    process("node", pid: 7, cpu: 3, memory: 50),
                    process("claude", pid: 5, cpu: 1, memory: 400),
                    process("uv", pid: 9, cpu: 3, memory: 50),
                ]),
            ],
            [pane("p:d", "nvim", cpu: 0, memory: 1)],
        ])
        let byMemory = SessionList.sorted([tree], by: .memory)[0]
        #expect(byMemory.tabs.map(\.id) == ["s/0", "s/1"])
        // Ties at 10 by title ("zsh" = "zsh"), then id.
        #expect(byMemory.tabs[0].panes.map(\.id) == ["p:c", "p:a", "p:b"])
        // node and uv tie at 50: by name.
        #expect(byMemory.tabs[0].panes[0].processes.map(\.pid) == [5, 7, 9])

        let byCpu = SessionList.sorted([tree], by: .cpu)[0]
        #expect(byCpu.tabs.map(\.id) == ["s/0", "s/1"])
        #expect(byCpu.tabs[0].panes.map(\.id) == ["p:b", "p:c", "p:a"])
        // node and uv tie at 3: by name; claude last.
        #expect(byCpu.tabs[0].panes[1].processes.map(\.pid) == [7, 9, 5])
    }

    @Test func memorySortsByResidentSizeNotFootprint() {
        // "swapped" has the larger footprint but less in RAM.
        let swapped = session("s:swapped", "swapped", cpu: 0, memory: 0, tabs: [[pane("p:1", "a", cpu: 0, memory: 9_000, resident: 100)]])
        let busy = session("s:busy", "busy", cpu: 0, memory: 0, tabs: [[pane("p:2", "b", cpu: 0, memory: 1_000, resident: 800)]])
        #expect(SessionList.sorted([swapped, busy], by: .memory).map(\.id) == ["s:busy", "s:swapped"])
        #expect(SessionList.value(busy, .memory) == 800)
        let panes = SessionList.sorted(swapped.panes + busy.panes, by: .memory)
        #expect(panes.map(\.id) == ["p:2", "p:1"])
    }

    @Test func invalidCpuSortsAsZero() {
        let odd = [
            session("s:nan", "a", cpu: .nan, memory: 0, tabs: []),
            session("s:one", "b", cpu: 1, memory: 0, tabs: []),
        ]
        #expect(SessionList.sorted(odd, by: .cpu).map(\.id) == ["s:one", "s:nan"])
    }
}

@Suite struct SessionsSummaryTests {
    @Test func countsTotalsClaudeAndShares() throws {
        let summary = SessionsSummary(Fixtures.sessions.sessions)
        #expect(summary.sessionCount == 4)
        #expect(summary.tabCount == 5)
        #expect(summary.paneCount == 9)
        #expect(summary.claudePaneCount == 4)

        let panes = Fixtures.sessions.sessions.flatMap(\.panes)
        let claude = panes.filter { $0.kind == .claude }
        #expect(summary.claudeMemory.resident == claude.reduce(0) { $0 + $1.residentBytes })
        #expect(summary.claudeMemory.footprint == claude.reduce(0) { $0 + $1.memoryBytes })
        #expect(summary.memory.resident == Fixtures.sessions.sessions.reduce(0) { $0 + $1.residentBytes })
        #expect(summary.memory.footprint == Fixtures.sessions.sessions.reduce(0) { $0 + $1.memoryBytes })
        #expect(abs(summary.cpuPercent - Fixtures.sessions.sessions.reduce(0) { $0 + $1.cpuPercent }) < 1e-9)

        #expect(summary.shares.map(\.label) == ["computa", "website", "dotfiles", "scratch"])
        #expect(abs(summary.shares.reduce(0) { $0 + $1.fraction } - 1) < 1e-9)
        let computa = try #require(Fixtures.sessions.sessions.first { $0.label == "computa" })
        #expect(abs(summary.shares[0].fraction - Double(computa.residentBytes) / Double(summary.memory.shownBytes)) < 1e-12)
    }

    @Test func oneSessionWithUnknownResidentMakesTheTotalAndSharesFootprint() throws {
        // "b" is from an older daemon: no resident size, no processes to add up.
        let summary = SessionsSummary([
            session("s:a", "a", cpu: 0, memory: 300, tabs: [[pane("p", "zsh", cpu: 0, memory: 300, resident: 100)]]),
            session("s:b", "b", cpu: 0, memory: 100, tabs: [[pane("q", "zsh", cpu: 0, memory: 100, resident: 0)]]),
        ])
        #expect(summary.memory == SessionMemory(resident: nil, footprint: 400))
        #expect(summary.memory.isFootprintOnly)
        #expect(summary.shares.map(\.label) == ["a", "b"])
        #expect(abs(summary.shares[0].fraction - 0.75) < 1e-12)
    }

    @Test func allZeroMemoryGivesNoSharesInsteadOfDividingByZero() {
        let summary = SessionsSummary([
            session("s:a", "a", cpu: 0, memory: 0, tabs: [[pane("p", "zsh", cpu: 0, memory: 0)]]),
            session("s:b", "b", cpu: 0, memory: 0, tabs: []),
        ])
        #expect(summary.sessionCount == 2)
        #expect(summary.paneCount == 1)
        #expect(summary.memory == SessionMemory(resident: 0, footprint: 0))
        #expect(summary.shares.isEmpty)
    }

    @Test func noSessions() {
        let summary = SessionsSummary([])
        #expect(summary == SessionsSummary([]))
        #expect(summary.sessionCount == 0)
        #expect(summary.claudePaneCount == 0)
        #expect(summary.shares.isEmpty)
    }
}

@Suite struct ClaudePopoverTextTests {
    @Test func countsClaudePanesAndTheirMemory() {
        let gib: UInt64 = 1 << 30
        let snapshot = SessionsSnapshot(
            time: Fixtures.now, rex: RexStatus(reachable: true, problem: "", version: ""),
            sessions: [
                session("s:a", "a", cpu: 0, memory: 0, tabs: [
                    [pane("p1", "claude", cpu: 0, memory: 2 * gib, kind: .claude), pane("p2", "zsh", cpu: 0, memory: gib, kind: .shell)],
                    [pane("p3", "claude", cpu: 0, memory: gib + gib / 5, kind: .claude)],
                ]),
                session("s:b", "b", cpu: 0, memory: 0, tabs: [[pane("p4", "claude", cpu: 0, memory: gib, kind: .claude)]]),
            ]
        )
        #expect(ClaudeUsage.popoverText(snapshot) == "3 panes · 4.2 GB")
    }

    @Test func singularForOnePane() {
        let snapshot = SessionsSnapshot(
            time: Fixtures.now, rex: RexStatus(reachable: true, problem: "", version: ""),
            sessions: [session("s", "s", cpu: 0, memory: 0, tabs: [[pane("p", "claude", cpu: 0, memory: 300 << 20, kind: .claude)]])]
        )
        #expect(ClaudeUsage.popoverText(snapshot) == "1 pane · 300 MB")
    }

    @Test func showsResidentSizeNotFootprint() {
        let snapshot = SessionsSnapshot(
            time: Fixtures.now, rex: RexStatus(reachable: true, problem: "", version: ""),
            sessions: [session("s", "s", cpu: 0, memory: 0, tabs: [[
                pane("p", "claude", cpu: 0, memory: 900 << 20, resident: 300 << 20, kind: .claude),
            ]])]
        )
        #expect(ClaudeUsage.popoverText(snapshot) == "1 pane · 300 MB")
    }

    @Test func anOlderDaemonsFootprintIsLabelledAsSuch() throws {
        let text = try #require(ClaudeUsage.popoverText(Fixtures.sessionsOldDaemon))
        let footprint = Fixtures.sessionsOldDaemon.sessions.flatMap(\.panes).filter(\.isClaude).reduce(0) { $0 + $1.memoryBytes }
        #expect(text == "\(Format.memory(footprint)) footprint")
        #expect(!text.contains("0 B"))
    }

    @Test func hiddenWithoutClaudeWhenRexIsDownOrWithoutASnapshot() {
        #expect(ClaudeUsage.popoverText(nil) == nil)
        #expect(ClaudeUsage.popoverText(Fixtures.sessionsRexDown) == nil)
        #expect(ClaudeUsage.popoverText(Fixtures.sessionsEmpty) == nil)
        var unreachable = Fixtures.sessions
        unreachable.rex.reachable = false
        #expect(ClaudeUsage.popoverText(unreachable) == nil)
        let shellsOnly = SessionsSnapshot(
            time: Fixtures.now, rex: RexStatus(reachable: true, problem: "", version: ""),
            sessions: [session("s", "s", cpu: 0, memory: 0, tabs: [[pane("p", "zsh", cpu: 0, memory: 5, kind: .shell)]])]
        )
        #expect(ClaudeUsage.popoverText(shellsOnly) == nil)
    }
}

@Suite struct WorkingDirectoryTests {
    @Test func abbreviatesAnyHomeFolder() {
        #expect(WorkingDirectory.display("/Users/morgan") == "~")
        #expect(WorkingDirectory.display("/Users/morgan/") == "~")
        #expect(WorkingDirectory.display("/Users/morgan/Documents/computa") == "~/Documents/computa")
        #expect(WorkingDirectory.display("/Users/someone/x") == "~/x")
    }

    @Test func leavesOtherPathsAlone() {
        #expect(WorkingDirectory.display("/Users") == "/Users")
        #expect(WorkingDirectory.display("/Users/") == "/Users/")
        #expect(WorkingDirectory.display("/Usersfoo/x") == "/Usersfoo/x")
        #expect(WorkingDirectory.display("/tmp") == "/tmp")
        #expect(WorkingDirectory.display("relative/Users/morgan") == "relative/Users/morgan")
        #expect(WorkingDirectory.display("") == "")
    }

    @Test func shortensLongPathsInTheMiddleKeepingTheLastFolders() {
        let path = "/Users/morgan/Documents/projects/computa/app/Sources/ComputaCore"
        let short = WorkingDirectory.display(path, maxLength: 30)
        #expect(short == "~/…/app/Sources/ComputaCore")
        #expect(short.count <= 30)
        #expect(WorkingDirectory.display("/opt/homebrew/Cellar/node/22.1.0/lib/node_modules", maxLength: 30) == "/opt/…/22.1.0/lib/node_modules")
    }

    @Test func cutsCharactersWhenEvenTheLastFolderIsTooLong() {
        let short = WorkingDirectory.display("~/" + String(repeating: "a", count: 40), maxLength: 20)
        #expect(short.count == 20)
        #expect(short.contains("…"))
        #expect(short.hasPrefix("~/"))
    }

    @Test func shortPathsAreUnchanged() {
        #expect(WorkingDirectory.display("/Users/morgan/a/b", maxLength: 8) == "~/a/b")
    }
}
