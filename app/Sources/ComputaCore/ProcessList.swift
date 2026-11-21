import Foundation

/// What the process list is sorted by. `memory` means memory in RAM now, not footprint: on a
/// machine that is swapping, footprints add up to more than the RAM installed. `network` means
/// download and upload together.
public enum ProcessMetric: Sendable, Hashable, Identifiable {
    case cpu, memory, network

    public var id: Self { self }

    /// The label on a sort control.
    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        }
    }
}

/// Sorting and searching the grouped process list. Pure functions, so they are testable.
public enum ProcessList {
    /// Groups largest first by `metric`, each group's processes sorted the same way.
    ///
    /// The daemon sends groups in no particular order, so equal values are ordered by name and
    /// then id (processes: name, then pid). Rows with equal values then keep their places from
    /// one snapshot to the next instead of swapping.
    ///
    /// - Parameter residentReported: False when the daemon reports no resident sizes (it is
    ///   older than the field); memory then sorts by footprint, the only figure there is.
    public static func sorted(
        _ groups: [ProcessGroup], by metric: ProcessMetric, residentReported: Bool = true
    ) -> [ProcessGroup] {
        let key = SortKey(metric, residentReported: residentReported)
        return groups
            .map { group in
                var group = group
                group.processes = sorted(group.processes, key: key)
                return group
            }
            .sorted { a, b in
                let (x, y) = (key.value(a), key.value(b))
                if x != y { return x > y }
                return tieBreak(a.name, b.name) ?? (a.id < b.id)
            }
    }

    /// Processes largest first by `metric`; ties by name, then pid.
    public static func sorted(_ processes: [ProcessEntry], by metric: ProcessMetric) -> [ProcessEntry] {
        sorted(processes, key: SortKey(metric, residentReported: true))
    }

    /// Groups whose name, or the name of any of whose processes, contains `query`, ignoring case.
    /// A blank query keeps every group. Matching groups keep all their processes.
    public static func filtered(_ groups: [ProcessGroup], query: String) -> [ProcessGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return groups }
        return groups.filter { group in
            matches(group.name, needle) || group.processes.contains { matches($0.name, needle) }
        }
    }

    /// Filters, then sorts: what the list shows.
    public static func visible(
        _ groups: [ProcessGroup], query: String, metric: ProcessMetric, residentReported: Bool = true
    ) -> [ProcessGroup] {
        sorted(filtered(groups, query: query), by: metric, residentReported: residentReported)
    }

    public static func value(_ group: ProcessGroup, _ metric: ProcessMetric) -> Double {
        SortKey(metric, residentReported: true).value(group)
    }

    public static func value(_ process: ProcessEntry, _ metric: ProcessMetric) -> Double {
        SortKey(metric, residentReported: true).value(process)
    }

    /// The text for a group's or a process's value in the list: a CPU share, a memory size, or
    /// a total transfer rate.
    public static func valueText(_ value: Double, _ metric: ProcessMetric) -> String {
        switch metric {
        case .cpu: Format.cpuShare(value)
        case .memory: Format.memory(UInt64(max(0, value.isFinite ? value : 0)))
        case .network: Format.rate(value)
        }
    }

    /// A process's value where footprints are shown: a Rex session's list, whose pane totals
    /// are footprints.
    public static func footprintValueText(_ process: ProcessEntry, _ metric: ProcessMetric) -> String {
        switch metric {
        case .cpu, .network: valueText(value(process, metric), metric)
        case .memory: Format.memory(process.memoryBytes)
        }
    }

    private static func sorted(_ processes: [ProcessEntry], key: SortKey) -> [ProcessEntry] {
        processes.sorted { a, b in
            let (x, y) = (key.value(a), key.value(b))
            if x != y { return x > y }
            return tieBreak(a.name, b.name) ?? (a.pid < b.pid)
        }
    }

    private static func matches(_ name: String, _ needle: String) -> Bool {
        name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Orders by name ignoring case, or nil when the names compare equal.
    private static func tieBreak(_ a: String, _ b: String) -> Bool? {
        switch a.caseInsensitiveCompare(b) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: nil
        }
    }
}

/// The number a row is sorted by.
private enum SortKey {
    case cpu, resident, footprint, traffic

    init(_ metric: ProcessMetric, residentReported: Bool) {
        switch metric {
        case .cpu: self = .cpu
        case .memory: self = residentReported ? .resident : .footprint
        case .network: self = .traffic
        }
    }

    func value(_ group: ProcessGroup) -> Double {
        switch self {
        case .cpu: finite(group.cpuPercent)
        case .resident: Double(group.residentBytes)
        case .footprint: Double(group.memoryBytes)
        case .traffic: finite(group.receiveBytesPerSecond) + finite(group.sendBytesPerSecond)
        }
    }

    func value(_ process: ProcessEntry) -> Double {
        switch self {
        case .cpu: finite(process.cpuPercent)
        case .resident: Double(process.residentBytes)
        case .footprint: Double(process.memoryBytes)
        case .traffic: finite(process.receiveBytesPerSecond) + finite(process.sendBytesPerSecond)
        }
    }

    private func finite(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }
}
