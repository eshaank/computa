import Foundation

/// Where the Sessions tab is: every session, one session's panes, or one pane's processes.
public enum SessionPlace: Sendable, Equatable {
    case overview
    case session(RexSession)
    case pane(RexPane, tab: RexTab, session: RexSession)

    /// The session shown, at either deeper level.
    public var session: RexSession? {
        switch self {
        case .overview: nil
        case .session(let session), .pane(_, _, let session): session
        }
    }
}

/// A session's panes under one tab's heading. `tab` is nil when the session has a single tab,
/// so no heading is shown.
public struct SessionPaneGroup: Sendable, Equatable, Identifiable {
    public var tab: RexTab?
    public var panes: [RexPane]
    public var id: String

    public init(tab: RexTab?, panes: [RexPane], id: String) {
        self.tab = tab
        self.panes = panes
        self.id = id
    }
}

/// The drill-in as pure functions, so it is testable. The open path is a set of Rex ids (a
/// session's, and perhaps one of its panes'), because ids are stable between snapshots: the
/// place survives every refresh, and falls back a level when what it pointed at is gone.
public enum SessionNavigation {
    /// The deepest place `open` still points at in `sessions`. A pane that has closed falls back
    /// to its session, a session that has closed to the overview. When the set names several
    /// sessions (it never should), the first in `sessions` wins.
    public static func place(open: Set<String>, in sessions: [RexSession]) -> SessionPlace {
        guard !open.isEmpty, let session = sessions.first(where: { open.contains($0.id) }) else { return .overview }
        for tab in session.tabs {
            if let pane = tab.panes.first(where: { open.contains($0.id) }) {
                return .pane(pane, tab: tab, session: session)
            }
        }
        return .session(session)
    }

    /// The open path for a session.
    public static func path(to session: RexSession) -> Set<String> { [session.id] }

    /// The open path for a pane in a session.
    public static func path(to pane: RexPane, in session: RexSession) -> Set<String> { [session.id, pane.id] }

    /// One level up from `place`: a pane goes back to its session, a session to the overview.
    public static func back(from place: SessionPlace) -> Set<String> {
        switch place {
        case .overview, .session: []
        case .pane(_, _, let session): path(to: session)
        }
    }

    /// The session's panes, grouped by tab when it has more than one. Tabs keep the session's
    /// order (Rex's, or the sort's); empty tabs are left out.
    public static func groups(_ session: RexSession) -> [SessionPaneGroup] {
        guard session.tabs.count > 1 else {
            return [SessionPaneGroup(tab: nil, panes: session.panes, id: session.id)]
        }
        return session.tabs.filter { !$0.panes.isEmpty }.map { SessionPaneGroup(tab: $0, panes: $0.panes, id: $0.id) }
    }
}
