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
    /// Whether the per-process network rates can be trusted. Nil when the daemon sent no status:
    /// the request did not ask for traffic, or the daemon is too old to measure it.
    public var network: ProcessNetworkStatus?

    public init(
        time: Date, groups: [ProcessGroup], hidden: HiddenProcesses?, processCount: Int,
        network: ProcessNetworkStatus? = nil
    ) {
        self.time = time
        self.groups = groups
        self.hidden = hidden
        self.processCount = processCount
        self.network = network
    }

    /// False when no process reports a resident size: a daemon older than the field sends 0
    /// for it. The Mem column then says "not reported" instead of a wrong "0 B".
    public var reportsResidentSize: Bool {
        groups.contains { group in group.processes.contains { $0.residentBytes > 0 } }
    }
}

/// Whether a snapshot's per-process network rates can be trusted.
public struct ProcessNetworkStatus: Sendable, Equatable {
    /// False before the daemon has two readings to compare, and when it cannot measure. Every
    /// rate is then 0.
    public var available: Bool
    /// Why the rates are not available, in words a person can act on. Empty otherwise.
    public var problem: String

    public init(available: Bool, problem: String = "") {
        self.available = available
        self.problem = problem
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
    /// Summed here rather than taken from the daemon, which an older daemon sends as 0.
    public var residentBytes: UInt64 { processes.reduce(0) { $0 + $1.residentBytes } }

    /// Footprint minus what is in RAM, never below zero: roughly what is compressed or in swap.
    public var compressedOrSwappedBytes: UInt64 { memoryBytes.subtractingClamped(residentBytes) }

    /// Download and upload rates added up over the group's processes, in bytes per second.
    public var receiveBytesPerSecond: Double { processes.reduce(0) { $0 + $1.receiveBytesPerSecond } }
    public var sendBytesPerSecond: Double { processes.reduce(0) { $0 + $1.sendBytesPerSecond } }

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
    /// Network traffic over every interface, loopback included, in bytes per second. Zero
    /// unless the stream asked for traffic.
    public var receiveBytesPerSecond: Double
    public var sendBytesPerSecond: Double

    public var id: Int32 { pid }

    /// Footprint minus resident size, never below zero (a process can have more in RAM than its
    /// footprint, since shared pages count in full): roughly what is compressed or in swap.
    public var compressedOrSwappedBytes: UInt64 { memoryBytes.subtractingClamped(residentBytes) }

    public init(
        pid: Int32, parentPid: Int32, name: String, path: String, cpuPercent: Double,
        memoryBytes: UInt64, residentBytes: UInt64,
        receiveBytesPerSecond: Double = 0, sendBytesPerSecond: Double = 0
    ) {
        self.pid = pid
        self.parentPid = parentPid
        self.name = name
        self.path = path
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.residentBytes = residentBytes
        self.receiveBytesPerSecond = receiveBytesPerSecond
        self.sendBytesPerSecond = sendBytesPerSecond
    }
}

extension UInt64 {
    /// `self - other`, or 0 when `other` is larger.
    public func subtractingClamped(_ other: UInt64) -> UInt64 { self > other ? self - other : 0 }
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
            processCount: Int(message.processCount),
            network: message.hasNetwork
                ? ProcessNetworkStatus(available: message.network.available, problem: message.network.problem)
                : nil
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
            processes: message.processes.map(ProcessEntry.withTraffic)
        )
    }
}

extension ProcessEntry {
    /// A process from the process stream, with its network rates. (Session snapshots map
    /// processes without them, in `SessionModels.swift`.)
    /// A static function rather than an initialiser, so `ProcessEntry.init` stays unambiguous.
    package static func withTraffic(_ message: Computa_V1_Process) -> ProcessEntry {
        ProcessEntry(
            pid: message.pid, parentPid: message.parentPid, name: message.name, path: message.path,
            cpuPercent: message.cpuPercent, memoryBytes: message.memoryBytes, residentBytes: message.residentBytes,
            receiveBytesPerSecond: message.rxBytesPerSec, sendBytesPerSecond: message.txBytesPerSec
        )
    }
}
