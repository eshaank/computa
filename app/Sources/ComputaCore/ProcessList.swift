import Foundation

/// What the process list is sorted by. `memory` means memory in RAM now, not footprint: on a
/// machine that is swapping, footprints add up to more than the RAM installed.
public enum ProcessMetric: Sendable, Hashable, Identifiable {
    case cpu, memory

    public var id: Self { self }

    /// The label on a sort control.
    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
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
    public static func sorted(_ groups: [ProcessGroup], by metric: ProcessMetric) -> [ProcessGroup] {
        groups
            .map { group in
                var group = group
                group.processes = sorted(group.processes, by: metric)
                return group
            }
            .sorted { a, b in
                let (x, y) = (value(a, metric), value(b, metric))
                if x != y { return x > y }
                return tieBreak(a.name, b.name) ?? (a.id < b.id)
            }
    }

    /// Processes largest first by `metric`; ties by name, then pid.
    public static func sorted(_ processes: [ProcessEntry], by metric: ProcessMetric) -> [ProcessEntry] {
        processes.sorted { a, b in
            let (x, y) = (value(a, metric), value(b, metric))
            if x != y { return x > y }
            return tieBreak(a.name, b.name) ?? (a.pid < b.pid)
        }
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
    public static func visible(_ groups: [ProcessGroup], query: String, metric: ProcessMetric) -> [ProcessGroup] {
        sorted(filtered(groups, query: query), by: metric)
    }

    public static func value(_ group: ProcessGroup, _ metric: ProcessMetric) -> Double {
        switch metric {
        case .cpu: finite(group.cpuPercent)
        case .memory: Double(group.residentBytes)
        }
    }

    public static func value(_ process: ProcessEntry, _ metric: ProcessMetric) -> Double {
        switch metric {
        case .cpu: finite(process.cpuPercent)
        case .memory: Double(process.residentBytes)
        }
    }

    /// The text for a group's or a process's value in the list.
    public static func valueText(_ value: Double, _ metric: ProcessMetric) -> String {
        switch metric {
        case .cpu: Format.cpuShare(value)
        case .memory: Format.memory(UInt64(max(0, value)))
        }
    }

    /// The second figure in a memory row: the footprint. Nil for CPU, which has one figure.
    public static func totalText(footprint: UInt64, _ metric: ProcessMetric) -> String? {
        metric == .memory ? Format.memory(footprint) : nil
    }

    /// A process's value where footprints are shown: a Rex session's list, whose pane totals
    /// are footprints.
    public static func footprintValueText(_ process: ProcessEntry, _ metric: ProcessMetric) -> String {
        switch metric {
        case .cpu: valueText(value(process, .cpu), .cpu)
        case .memory: Format.memory(process.memoryBytes)
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

    private static func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }
}
