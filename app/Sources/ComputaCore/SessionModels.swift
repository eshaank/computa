import Foundation

/// Rex's sessions, tabs and panes at one moment, with the usage of the processes in each pane.
public struct SessionsSnapshot: Sendable, Equatable {
    public var time: Date
    public var rex: RexStatus
    /// Empty when Rex cannot be reached. In no particular order; `SessionList` sorts them.
    public var sessions: [RexSession]

    public init(time: Date, rex: RexStatus, sessions: [RexSession]) {
        self.time = time
        self.rex = rex
        self.sessions = sessions
    }
}

/// Whether the daemon could reach Rex.
public struct RexStatus: Sendable, Equatable {
    public var reachable: Bool
    /// When not reachable, why, in words a person can act on. Empty when reachable, and possibly
    /// empty when the daemon gave no reason.
    public var problem: String
    /// For example "0.1.0-preview.14". Empty when unknown.
    public var version: String

    public init(reachable: Bool, problem: String, version: String) {
        self.reachable = reachable
        self.problem = problem
        self.version = version
    }
}

/// A Rex session. Usage is added up over the processes the daemon can read.
public struct RexSession: Sendable, Equatable, Identifiable {
    /// Rex's id, for example "session:01a1f5ee-…". Stable between snapshots.
    public var id: String
    public var label: String
    /// 100 is one core fully busy.
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var processCount: Int
    /// In Rex's order.
    public var tabs: [RexTab]

    public init(
        id: String, label: String, cpuPercent: Double, memoryBytes: UInt64, processCount: Int, tabs: [RexTab]
    ) {
        self.id = id
        self.label = label
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.processCount = processCount
        self.tabs = tabs
    }

    /// Every pane in every tab, in Rex's order.
    public var panes: [RexPane] { tabs.flatMap(\.panes) }
    public var paneCount: Int { tabs.reduce(0) { $0 + $1.panes.count } }
    /// Panes running Claude Code.
    public var claudePaneCount: Int { panes.filter(\.isClaude).count }
}

/// A tab. Rex calls it a window.
public struct RexTab: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var processCount: Int
    public var panes: [RexPane]

    public init(
        id: String, label: String, cpuPercent: Double, memoryBytes: UInt64, processCount: Int, panes: [RexPane]
    ) {
        self.id = id
        self.label = label
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.processCount = processCount
        self.panes = panes
    }
}

/// What runs in a pane.
public enum PaneKind: Sendable, Equatable {
    case unspecified
    /// Nothing but the shell.
    case shell
    /// Some other program in the foreground.
    case program
    /// Claude Code.
    case claude
}

/// A terminal pane. Rex calls it a block.
public struct RexPane: Sendable, Equatable, Identifiable {
    /// Rex's id, for example "block:01a1f5ee-…". Stable between snapshots.
    public var id: String
    public var label: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    /// Every process started in the pane, readable or not.
    public var processCount: Int
    public var kind: PaneKind
    /// The foreground program, for example "claude", "zsh" or "nvim". Empty when unknown.
    public var program: String
    /// The foreground program's working directory. Empty when unknown.
    public var workingDirectory: String
    /// The readable processes, in no particular order.
    public var processes: [ProcessEntry]

    public init(
        id: String, label: String, cpuPercent: Double, memoryBytes: UInt64, processCount: Int, kind: PaneKind,
        program: String, workingDirectory: String, processes: [ProcessEntry]
    ) {
        self.id = id
        self.label = label
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.processCount = processCount
        self.kind = kind
        self.program = program
        self.workingDirectory = workingDirectory
        self.processes = processes
    }

    public var isClaude: Bool { kind == .claude }

    /// The name shown for the pane: the program, else Rex's label, else "pane".
    public var title: String {
        if !program.isEmpty { return program }
        return label.isEmpty ? "pane" : label
    }

    /// "+N" for the readable processes beyond the first, as in the process list; nil for one or none.
    public var badge: String? { processes.count > 1 ? "+\(processes.count - 1)" : nil }
}

// MARK: - Mapping from the generated messages

extension SessionsSnapshot {
    package init(_ message: Computa_V1_SessionsSnapshot) {
        self.init(
            time: Date(unixMilliseconds: message.unixMs),
            // A missing status reads as unreachable with no reason, so the tab never claims Rex
            // is fine when the daemon said nothing.
            rex: message.hasRex ? RexStatus(message.rex) : RexStatus(reachable: false, problem: "", version: ""),
            sessions: message.sessions.map(RexSession.init)
        )
    }
}

extension RexStatus {
    package init(_ message: Computa_V1_RexStatus) {
        self.init(reachable: message.reachable, problem: message.problem, version: message.version)
    }
}

extension RexSession {
    package init(_ message: Computa_V1_Session) {
        self.init(
            id: message.id, label: message.label, cpuPercent: message.cpuPercent, memoryBytes: message.memoryBytes,
            processCount: Int(message.processCount), tabs: message.windows.map(RexTab.init)
        )
    }
}

extension RexTab {
    package init(_ message: Computa_V1_SessionWindow) {
        self.init(
            id: message.id, label: message.label, cpuPercent: message.cpuPercent, memoryBytes: message.memoryBytes,
            processCount: Int(message.processCount), panes: message.panes.map(RexPane.init)
        )
    }
}

extension RexPane {
    package init(_ message: Computa_V1_Pane) {
        self.init(
            id: message.id, label: message.label, cpuPercent: message.cpuPercent, memoryBytes: message.memoryBytes,
            processCount: Int(message.processCount), kind: PaneKind(message.kind), program: message.program,
            workingDirectory: message.workingDirectory, processes: message.processes.map(ProcessEntry.init)
        )
    }
}

extension PaneKind {
    package init(_ kind: Computa_V1_PaneKind) {
        switch kind {
        case .shell: self = .shell
        case .program: self = .program
        case .claude: self = .claude
        case .unspecified, .UNRECOGNIZED: self = .unspecified
        }
    }
}

extension ProcessEntry {
    package init(_ message: Computa_V1_Process) {
        self.init(
            pid: message.pid, parentPid: message.parentPid, name: message.name, path: message.path,
            cpuPercent: message.cpuPercent, memoryBytes: message.memoryBytes, residentBytes: message.residentBytes
        )
    }
}
