/// The dashboard's tabs, in display order. Adding a tab means adding a case here and its look in
/// `ComputaUI`.
public enum DashboardTab: String, CaseIterable, Sendable, Hashable, Identifiable {
    case cpu, memory, network, disk, sessions

    public var id: String { rawValue }

    /// The short label on the tab control.
    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Mem"
        case .network: "Net"
        case .disk: "Disk"
        case .sessions: "Sessions"
        }
    }

    /// What the process list is sorted by on this tab, or nil when the tab shows no process list.
    /// The process stream only runs while such a tab is showing.
    public var processMetric: ProcessMetric? {
        switch self {
        case .cpu: .cpu
        case .memory: .memory
        case .network: .network
        case .disk, .sessions: nil
        }
    }

    public var showsProcesses: Bool { processMetric != nil }

    /// Whether the tab's process list shows network rates, which costs the daemon extra work,
    /// so the process stream asks for them only then.
    public var needsProcessTraffic: Bool { processMetric == .network }

    /// The Sessions tab shows Rex's sessions instead of a history chart. The sessions stream runs
    /// while it is showing (and while the popover is open).
    public var showsSessions: Bool { self == .sessions }

    /// Whether the tab has a history chart and range picker.
    public var showsHistory: Bool { self != .sessions }
}

/// How far back the dashboard chart reaches.
public enum HistoryRange: String, CaseIterable, Sendable, Hashable, Identifiable {
    case fiveMinutes, fifteenMinutes, oneHour

    public var id: String { rawValue }

    public var windowSeconds: UInt32 {
        switch self {
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .oneHour: 3600
        }
    }

    public var title: String {
        switch self {
        case .fiveMinutes: "5m"
        case .fifteenMinutes: "15m"
        case .oneHour: "1h"
        }
    }
}
