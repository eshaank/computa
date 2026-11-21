import Foundation

/// Sorting the Rex session tree. Pure functions, so they are testable.
public enum SessionList {
    /// Sessions largest first by `metric`; inside each, every tab's panes sorted the same way and
    /// every pane's processes too. Tabs keep Rex's order.
    ///
    /// The daemon sends sessions in no particular order, so equal values are ordered by label and
    /// then id (panes: title, then id; processes: name, then pid), and rows keep their places from
    /// one snapshot to the next.
    public static func sorted(_ sessions: [RexSession], by metric: ProcessMetric) -> [RexSession] {
        sessions
            .map { session in
                var session = session
                session.tabs = session.tabs.map { tab in
                    var tab = tab
                    tab.panes = sorted(tab.panes, by: metric)
                    return tab
                }
                return session
            }
            .sorted { a, b in
                let (x, y) = (value(a, metric), value(b, metric))
                if x != y { return x > y }
                return tieBreak(a.label, b.label) ?? (a.id < b.id)
            }
    }

    /// Panes largest first by `metric`, each pane's processes sorted the same way.
    public static func sorted(_ panes: [RexPane], by metric: ProcessMetric) -> [RexPane] {
        panes
            .map { pane in
                var pane = pane
                pane.processes = ProcessList.sorted(pane.processes, by: metric)
                return pane
            }
            .sorted { a, b in
                let (x, y) = (value(a, metric), value(b, metric))
                if x != y { return x > y }
                return tieBreak(a.title, b.title) ?? (a.id < b.id)
            }
    }

    /// For memory, the resident size ("Mem"); where an older daemon left that unknown, the
    /// footprint, which is the figure the row then shows and labels.
    public static func value(_ session: RexSession, _ metric: ProcessMetric) -> Double {
        value(cpu: session.cpuPercent, memory: session.memory.shownBytes, metric)
    }

    public static func value(_ tab: RexTab, _ metric: ProcessMetric) -> Double {
        value(cpu: tab.cpuPercent, memory: tab.memory.shownBytes, metric)
    }

    public static func value(_ pane: RexPane, _ metric: ProcessMetric) -> Double {
        value(cpu: pane.cpuPercent, memory: pane.memory.shownBytes, metric)
    }

    private static func value(cpu: Double, memory: UInt64, _ metric: ProcessMetric) -> Double {
        switch metric {
        case .cpu: cpu.isFinite ? max(0, cpu) : 0
        case .memory: Double(memory)
        }
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

/// The figures in the Sessions tab's summary panel, and the popover's Claude row.
public struct SessionsSummary: Sendable, Equatable {
    /// One session's part of the total memory.
    public struct Share: Sendable, Equatable, Identifiable {
        public var id: String
        public var label: String
        /// 0...1. The shares of a summary add up to 1.
        public var fraction: Double
    }

    public var sessionCount = 0
    public var tabCount = 0
    public var paneCount = 0
    public var claudePaneCount = 0
    /// Over the Claude Code panes: resident ("Mem") and footprint.
    public var claudeMemory = SessionMemory(resident: 0, footprint: 0)
    /// Added up over the sessions, which the daemon adds up over their panes.
    public var cpuPercent: Double = 0
    /// Over every session: resident ("Mem") and footprint.
    public var memory = SessionMemory(resident: 0, footprint: 0)
    /// Largest first, ties by id. Shares of resident size, or of footprint when any session's
    /// resident size is unknown, so the bar never mixes the two. Empty when no session uses any
    /// memory, so nothing divides by zero.
    public var shares: [Share] = []

    /// The total as shown: resident, or footprint when that is unknown (`memory.isFootprintOnly`).
    public var memoryBytes: UInt64 { memory.shownBytes }
    /// The Claude Code panes' figure as shown, like `memoryBytes`.
    public var claudeMemoryBytes: UInt64 { claudeMemory.shownBytes }

    public init(_ sessions: [RexSession]) {
        var claude: [SessionMemory] = []
        for session in sessions {
            sessionCount += 1
            tabCount += session.tabs.count
            for pane in session.panes where pane.isClaude {
                claude.append(pane.memory)
            }
            paneCount += session.paneCount
            if session.cpuPercent.isFinite { cpuPercent += max(0, session.cpuPercent) }
        }
        claudePaneCount = claude.count
        claudeMemory = SessionMemory.total(claude)
        memory = SessionMemory.total(sessions.map(\.memory))
        let byResident = memory.resident != nil
        let total = Double(memory.shownBytes)
        guard total > 0 else { return }
        shares = sessions
            .map { session in
                let bytes = byResident ? session.memory.resident ?? 0 : session.memoryBytes
                return Share(id: session.id, label: session.label, fraction: Double(bytes) / total)
            }
            .sorted { a, b in a.fraction != b.fraction ? a.fraction > b.fraction : a.id < b.id }
    }
}

/// Text for the popover's "Claude Code" row.
public enum ClaudeUsage {
    /// For example "3 panes · 4.2 GB": the panes' resident size, what is in RAM now. When an older
    /// daemon leaves that unknown, "3 panes · 5.1 GB footprint". Nil when the row should be
    /// hidden: no snapshot (the stream is not connected), Rex unreachable, or no Claude Code pane.
    public static func popoverText(_ snapshot: SessionsSnapshot?) -> String? {
        guard let snapshot, snapshot.rex.reachable else { return nil }
        let summary = SessionsSummary(snapshot.sessions)
        guard summary.claudePaneCount > 0 else { return nil }
        let panes = summary.claudePaneCount == 1 ? "1 pane" : "\(summary.claudePaneCount) panes"
        let memory = summary.claudeMemory
        let suffix = memory.isFootprintOnly ? " footprint" : ""
        return "\(panes) · \(Format.memory(memory.shownBytes))\(suffix)"
    }
}

/// Working directories as the Sessions tab shows them.
public enum WorkingDirectory {
    /// Abbreviates a home folder (any path starting "/Users/<name>") to "~", then shortens paths
    /// longer than `maxLength` characters in the middle, keeping the start and as many of the
    /// last folders as fit: "~/Documents/…/app/Sources". Empty stays empty.
    public static func display(_ path: String, maxLength: Int = 44) -> String {
        let short = abbreviatingHome(path)
        guard short.count > maxLength, maxLength > 1 else { return short }
        return middleTruncated(short, maxLength: maxLength)
    }

    /// "/Users/name" → "~", "/Users/name/x" → "~/x"; anything else unchanged.
    public static func abbreviatingHome(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        // "/Users/name/…" splits into "", "Users", "name", …
        guard parts.count >= 3, parts[0].isEmpty, parts[1] == "Users", !parts[2].isEmpty else { return path }
        let rest = parts.dropFirst(3).joined(separator: "/")
        return rest.isEmpty ? "~" : "~/" + rest
    }

    private static func middleTruncated(_ path: String, maxLength: Int) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        // Keep the first folder ("~", or "" and the next for an absolute path).
        let headCount = parts.first == "" ? min(2, parts.count) : 1
        let head = parts.prefix(headCount).joined(separator: "/")
        var tail: [String] = []
        for part in parts.dropFirst(headCount).reversed() {
            let candidate = ([head, "…"] + [part] + tail).joined(separator: "/")
            guard candidate.count <= maxLength else { break }
            tail.insert(part, at: 0)
        }
        if !tail.isEmpty { return ([head, "…"] + tail).joined(separator: "/") }
        // Not even the last folder fits after the head: cut characters from the middle.
        let keep = maxLength - 1
        let front = path.prefix((keep + 1) / 2)
        let back = path.suffix(keep / 2)
        return "\(front)…\(back)"
    }
}
