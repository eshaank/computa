import AppKit
import ComputaCore
import ComputaUI
import SwiftUI

/// The Sessions tab: sorted by memory and by CPU with a session and a pane open, and each state
/// that replaces the list.
@MainActor
func renderSessionTabs(icons: any AppIconProviding) throws {
    let unsupported = DaemonProblem(
        kind: .unsupported, summary: "computad at 127.0.0.1:7300 does not offer this call yet. Update the daemon.",
        detail: "unimplemented"
    )
    let unreachable = DaemonProblem(
        kind: .unreachable, summary: "computad is not running at 127.0.0.1:7300.", detail: "unavailable"
    )
    // "computa" has two tabs; one of its Claude panes is open to its processes.
    let open: Set<String> = ["session:01a1", "block:01a1-a"]
    func shot(
        _ name: String, content: DashboardContent = dashboardContent(), metric: ProcessMetric = .memory,
        expanded: Set<String> = open, height: CGFloat = 760, actions: SessionActions = .none
    ) throws {
        let view = DashboardView(
            content: content, tab: .constant(.sessions), range: .constant(.fifteenMinutes), query: .constant(""),
            expanded: .constant([]), sessionsView: .constant(SessionsViewState(metric: metric, expanded: expanded)),
            icons: icons, sessionActions: actions
        )
        try renderWindow(view, size: CGSize(width: dashboardWidth, height: height), named: name)
    }
    try shot("dashboard-sessions-mem", height: 900)
    try shot("dashboard-sessions-cpu", metric: .cpu, height: 900)
    try shot("dashboard-sessions-collapsed", expanded: [])
    try shot("dashboard-sessions-rex-down", content: dashboardContent(sessions: Fixtures.sessionsRexDown))
    try shot("dashboard-sessions-empty", content: dashboardContent(sessions: Fixtures.sessionsEmpty))
    try shot("dashboard-sessions-loading", content: dashboardContent(sessionsState: .connecting))
    try shot("dashboard-sessions-need-update", content: dashboardContent(sessionsState: .daemonNotRunning(unsupported)))
    try shot(
        "dashboard-sessions-daemon-not-running",
        content: dashboardContent(sessionsState: .daemonNotRunning(unreachable))
    )
    try renderActionStates(shot: { name, actions, height in try shot(name, height: height, actions: actions) })
}

/// The action controls: a pane closing and a viewer opening, each outcome line, and the
/// confirmation sheet's content.
@MainActor
func renderActionStates(shot: (String, SessionActions, CGFloat) throws -> Void) throws {
    func actions(busy: Set<RexActionTarget> = [], _ outcome: RexActionOutcome?) -> SessionActions {
        SessionActions(busy: busy, outcome: outcome, perform: { _ in })
    }
    let notFound = RexLookup.notFound.error ?? .rexNotFound("")
    try shot("dashboard-sessions-busy", actions(busy: [.pane("block:01a1-b"), .session("session:5c21")], nil), 900)
    try shot(
        "dashboard-sessions-outcome-success",
        actions(RexActionOutcome(succeeded: true, text: RexActionResult.openedProcessViewer(program: "/opt/homebrew/bin/btop", windowID: "").summary)),
        640
    )
    try shot(
        "dashboard-sessions-outcome-not-installed",
        actions(RexActionOutcome(succeeded: false, text: RexActionError.actionsNotInstalled.description)), 640
    )
    try shot("dashboard-sessions-outcome-rex-not-found", actions(RexActionOutcome(succeeded: false, text: notFound.description)), 640)
    let pane = Fixtures.sessions.sessions[1].tabs[0].panes[0]
    try renderHosted(
        ClosePaneConfirmation(
            request: PaneCloseRequest(pane: pane, sessionID: "session:01a1", sessionLabel: "computa"),
            onCancel: {}, onConfirm: {}
        ),
        named: "close-pane-confirmation"
    )
}
