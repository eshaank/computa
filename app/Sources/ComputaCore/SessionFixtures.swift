import Foundation

/// Made-up but realistic Rex sessions for snapshots, previews and tests: four sessions, one
/// with two tabs, Claude Code running in three projects.
extension Fixtures {
    public static let sessions = SessionsSnapshot(
        time: now,
        rex: RexStatus(reachable: true, problem: "", version: "0.1.0-preview.14"),
        sessions: [
            SessionBuilder.session("website", id: "session:5c21", tabs: [
                SessionBuilder.tab("website", id: "window:5c21-1", panes: [
                    SessionBuilder.claude("block:5c21-a", directory: "/Users/eshaan/Projects/eshaan.dev", memory: 512, cpu: 3.4),
                    SessionBuilder.program("node", "block:5c21-b", directory: "/Users/eshaan/Projects/eshaan.dev", helpers: ["esbuild"], memory: 296, cpu: 7.9),
                ]),
            ]),
            SessionBuilder.session("computa", id: "session:01a1", tabs: [
                SessionBuilder.tab("app", id: "window:01a1-1", panes: [
                    SessionBuilder.claude("block:01a1-a", directory: "/Users/eshaan/Documents/computa", memory: 438, cpu: 12.6),
                    SessionBuilder.shell("block:01a1-b", directory: "/Users/eshaan/Documents/computa/app", memory: 5, cpu: 0),
                ]),
                SessionBuilder.tab("daemon", id: "window:01a1-2", panes: [
                    SessionBuilder.claude("block:01a1-c", directory: "/Users/eshaan/Documents/computa/daemon", memory: 401, cpu: 1.8),
                    SessionBuilder.program("cargo", "block:01a1-d", directory: "/Users/eshaan/Documents/computa/daemon/target/debug/build/computad-3f9a1c", helpers: ["rustc", "rustc"], memory: 1_240, cpu: 286.0),
                ]),
            ]),
            SessionBuilder.session("dotfiles", id: "session:9e07", tabs: [
                SessionBuilder.tab("dotfiles", id: "window:9e07-1", panes: [
                    SessionBuilder.program("nvim", "block:9e07-a", directory: "/Users/eshaan/.config/nvim", helpers: ["lua-language-server"], memory: 142, cpu: 0.6),
                    SessionBuilder.claude("block:9e07-b", directory: "/Users/eshaan/.config", memory: 356, cpu: 0.4),
                ]),
            ]),
            SessionBuilder.session("scratch", id: "session:77f3", tabs: [
                SessionBuilder.tab("scratch", id: "window:77f3-1", panes: [
                    SessionBuilder.shell("block:77f3-a", directory: "/tmp", memory: 4, cpu: 0),
                ]),
            ]),
        ]
    )

    /// The daemon could not reach Rex.
    public static let sessionsRexDown = SessionsSnapshot(
        time: now,
        rex: RexStatus(reachable: false, problem: "The rex command was not found.", version: ""),
        sessions: []
    )

    /// Rex is running with no session open.
    public static let sessionsEmpty = SessionsSnapshot(
        time: now, rex: RexStatus(reachable: true, problem: "", version: "0.1.0-preview.14"), sessions: []
    )
}

/// Builds fixture sessions whose totals add up from their panes, as the daemon's do.
enum SessionBuilder {
    private static let megabyte: UInt64 = 1 << 20

    static func session(_ label: String, id: String, tabs: [RexTab]) -> RexSession {
        RexSession(
            id: id, label: label, cpuPercent: tabs.reduce(0) { $0 + $1.cpuPercent },
            memoryBytes: tabs.reduce(0) { $0 + $1.memoryBytes }, processCount: tabs.reduce(0) { $0 + $1.processCount },
            tabs: tabs
        )
    }

    static func tab(_ label: String, id: String, panes: [RexPane]) -> RexTab {
        RexTab(
            id: id, label: label, cpuPercent: panes.reduce(0) { $0 + $1.cpuPercent },
            memoryBytes: panes.reduce(0) { $0 + $1.memoryBytes }, processCount: panes.reduce(0) { $0 + $1.processCount },
            panes: panes
        )
    }

    /// Claude Code with two MCP servers, started from the pane's shell.
    static func claude(_ id: String, directory: String, memory: UInt64, cpu: Double) -> RexPane {
        pane(id, kind: .claude, program: "claude", directory: directory, names: ["claude", "node", "uv", "zsh"], memory: memory, cpu: cpu)
    }

    static func program(_ name: String, _ id: String, directory: String, helpers: [String], memory: UInt64, cpu: Double) -> RexPane {
        pane(id, kind: .program, program: name, directory: directory, names: [name] + helpers + ["zsh"], memory: memory, cpu: cpu)
    }

    static func shell(_ id: String, directory: String, memory: UInt64, cpu: Double) -> RexPane {
        pane(id, kind: .shell, program: "zsh", directory: directory, names: ["zsh"], memory: memory, cpu: cpu)
    }

    /// The first process takes most of the usage; the shell at the end takes little.
    private static func pane(
        _ id: String, kind: PaneKind, program: String, directory: String, names: [String], memory: UInt64, cpu: Double
    ) -> RexPane {
        let weights = names.indices.map { index in index == 0 ? 6.0 : 1.0 / Double(index) }
        let sum = weights.reduce(0, +)
        // Pids follow from the id, so they are the same on every run.
        let base = Int32(id.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 50_000 }) + 10_000
        let processes = zip(names.indices, zip(names, weights)).map { index, entry -> ProcessEntry in
            let (name, weight) = entry
            let pid = base + Int32(index) * 7
            return ProcessEntry(
                pid: pid, parentPid: index == 0 ? base - 7 : base, name: name, path: "/usr/local/bin/\(name)",
                cpuPercent: cpu * weight / sum, memoryBytes: UInt64(Double(memory * megabyte) * weight / sum),
                residentBytes: UInt64(Double(memory * megabyte) * weight / sum)
            )
        }
        return RexPane(
            id: id, label: program, cpuPercent: processes.reduce(0) { $0 + $1.cpuPercent },
            memoryBytes: processes.reduce(0) { $0 + $1.memoryBytes }, processCount: processes.count,
            kind: kind, program: program, workingDirectory: directory, processes: processes
        )
    }
}
