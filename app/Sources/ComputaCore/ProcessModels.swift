import Foundation

/// The process list at one moment, grouped by app.
public struct ProcessSnapshot: Sendable, Equatable {
    public var time: Date
    /// Every group, in no particular order. `ProcessList` sorts them.
    public var groups: [ProcessGroup]
    /// Processes the daemon may not read. Nil when the daemon did not report them.
    public var hidden: HiddenProcesses?
    /// Every process on the machine, readable or not.
    public var processCount: Int

    public init(time: Date, groups: [ProcessGroup], hidden: HiddenProcesses?, processCount: Int) {
        self.time = time
        self.groups = groups
        self.hidden = hidden
        self.processCount = processCount
    }
}

/// Processes that belong together, such as an app and its helpers.
public struct ProcessGroup: Sendable, Equatable, Identifiable {
    /// The same from one snapshot to the next: the bundle path, "system", or "pid:<pid>".
    public var id: String
    public var name: String
    /// Empty when the group is not an app.
    public var bundlePath: String
    /// Added up over the group's processes; 100 is one core.
    public var cpuPercent: Double
    /// Footprint added up over the group's processes. See `ProcessEntry.memoryBytes`.
    public var memoryBytes: UInt64
    public var processes: [ProcessEntry]

    /// Memory in RAM now, added up over the group's processes. See `ProcessEntry.residentBytes`.
    public var residentBytes: UInt64 { processes.reduce(0) { $0 + $1.residentBytes } }

    /// The id the daemon gives the group of system processes.
    public static let systemID = "system"

    public init(
        id: String, name: String, bundlePath: String, cpuPercent: Double, memoryBytes: UInt64,
        processes: [ProcessEntry]
    ) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.processes = processes
    }

    public var isSystem: Bool { id == Self.systemID }

    /// Processes beyond the first, for the "+N" badge.
    public var extraProcessCount: Int { max(0, processes.count - 1) }

    /// "+N", or nil when the group has at most one process.
    public var badge: String? { extraProcessCount > 0 ? "+\(extraProcessCount)" : nil }
}

/// One process. Named so it does not clash with Foundation's `Process`.
public struct ProcessEntry: Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var parentPid: Int32
    public var name: String
    public var path: String
    /// 100 means one core fully busy.
    public var cpuPercent: Double
    /// Physical footprint, the "Memory" column in Activity Monitor: everything the process has
    /// allocated, counting what macOS has compressed or moved to swap at its full size. Added up
    /// over processes it can be far more than the RAM installed.
    public var memoryBytes: UInt64
    /// What is in RAM right now (resident size). It leaves out compressed and swapped memory,
    /// and counts a page shared between processes once in each of them.
    public var residentBytes: UInt64

    public var id: Int32 { pid }

    public init(
        pid: Int32, parentPid: Int32, name: String, path: String, cpuPercent: Double,
        memoryBytes: UInt64, residentBytes: UInt64
    ) {
        self.pid = pid
        self.parentPid = parentPid
        self.name = name
        self.path = path
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.residentBytes = residentBytes
    }
}

/// Processes owned by root or other users, whose usage a daemon running as the user cannot read.
/// Only their number is known.
public struct HiddenProcesses: Sendable, Equatable {
    public var processCount: Int

    public init(processCount: Int) {
        self.processCount = processCount
    }
}

extension ProcessSnapshot {
    package init(_ message: Computa_V1_ProcessSnapshot) {
        self.init(
            time: Date(unixMilliseconds: message.unixMs),
            groups: message.groups.map(ProcessGroup.init),
            hidden: message.hasHidden
                ? HiddenProcesses(processCount: Int(message.hidden.processCount))
                : nil,
            processCount: Int(message.processCount)
        )
    }
}

extension ProcessGroup {
    package init(_ message: Computa_V1_ProcessGroup) {
        self.init(
            id: message.id,
            name: message.name,
            bundlePath: message.bundlePath,
            cpuPercent: message.cpuPercent,
            memoryBytes: message.memoryBytes,
            processes: message.processes.map(ProcessEntry.init)
        )
    }
}
