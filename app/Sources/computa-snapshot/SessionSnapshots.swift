import AppKit
import ComputaCore
import ComputaUI
import SwiftUI

/// One Sessions tab render: what to show, where the drill-in is, and the window size.
@MainActor
struct SessionShot {
    var content: DashboardContent = dashboardContent(sessions: Fixtures.sessionsBusy)
    var metric: ProcessMetric = .memory
    var open: Set<String> = []
    var size = CGSize(width: dashboardWidth, height: 760)
    var actions: SessionActions = .none
}

@MainActor
func renderSessionShot(_ shot: SessionShot, icons: any AppIconProviding, named name: String) throws {
    let view = DashboardView(
        content: shot.content, tab: .constant(.sessions), range: .constant(.fifteenMinutes), query: .constant(""),
        expanded: .constant([]), sessionsView: .constant(SessionsViewState(metric: shot.metric, expanded: shot.open)),
        icons: icons, sessionActions: shot.actions
    )
    try renderWindow(view, size: shot.size, named: name)
}

/// The Sessions tab: the cards, a session opened, a pane opened, each state that replaces them,
/// and an older daemon's footprint-only figures.
@MainActor
func renderSessionTabs(icons: any AppIconProviding) throws {
    func shot(_ name: String, _ shot: SessionShot) throws { try renderSessionShot(shot, icons: icons, named: name) }
    let computa: Set<String> = ["session:01a1"]
    let claudePane: Set<String> = ["session:01a1", "block:01a1-a"]
    try shot("dashboard-sessions-mem", SessionShot())
    try shot("dashboard-sessions-cpu", SessionShot(metric: .cpu))
    try shot("dashboard-sessions-narrow", SessionShot(size: CGSize(width: minimumDashboardSize.width, height: 760)))
    try shot("dashboard-sessions-wide", SessionShot(size: CGSize(width: 1000, height: 760)))
    try shot("dashboard-sessions-session", SessionShot(open: computa))
    try shot("dashboard-sessions-session-long", SessionShot(open: ["session:e118"], size: CGSize(width: minimumDashboardSize.width, height: 900)))
    try shot("dashboard-sessions-pane", SessionShot(open: claudePane))
    try shot(
        "dashboard-sessions-pane-long",
        SessionShot(metric: .cpu, open: ["session:e118", "block:e118-b"], size: CGSize(width: minimumDashboardSize.width, height: 760))
    )
    // The pane id no longer exists: falls back to its session.
    try shot("dashboard-sessions-pane-gone", SessionShot(open: ["session:01a1", "block:gone"]))
    try shot("dashboard-sessions-old-daemon", SessionShot(content: dashboardContent(sessions: Fixtures.sessionsOldDaemon)))
    try shot(
        "dashboard-sessions-old-daemon-pane",
        SessionShot(content: dashboardContent(sessions: Fixtures.sessionsOldDaemon), open: claudePane)
    )
    try renderSessionStates(shot: shot)
    try renderActionStates(shot: shot)
}

/// The screens that replace the sessions.
@MainActor
func renderSessionStates(shot: (String, SessionShot) throws -> Void) throws {
    let unsupported = DaemonProblem(
        kind: .unsupported, summary: "computad at 127.0.0.1:7300 does not offer this call yet. Update the daemon.",
        detail: "unimplemented"
    )
    let unreachable = DaemonProblem(
        kind: .unreachable, summary: "computad is not running at 127.0.0.1:7300.", detail: "unavailable"
    )
    try shot("dashboard-sessions-rex-down", SessionShot(content: dashboardContent(sessions: Fixtures.sessionsRexDown)))
    try shot("dashboard-sessions-empty", SessionShot(content: dashboardContent(sessions: Fixtures.sessionsEmpty)))
    try shot("dashboard-sessions-loading", SessionShot(content: dashboardContent(sessionsState: .connecting)))
    try shot(
        "dashboard-sessions-need-update", SessionShot(content: dashboardContent(sessionsState: .daemonNotRunning(unsupported)))
    )
    try shot(
        "dashboard-sessions-daemon-not-running",
        SessionShot(content: dashboardContent(sessionsState: .daemonNotRunning(unreachable)))
    )
}

/// The action controls: a pane closing and a viewer opening, each outcome, the remote machine
/// without a label, and the confirmation sheet's content.
@MainActor
func renderActionStates(shot: (String, SessionShot) throws -> Void) throws {
    func actions(busy: Set<RexActionTarget> = [], _ outcome: RexActionOutcome?) -> SessionActions {
        SessionActions(busy: busy, outcome: outcome, perform: { _ in })
    }
    let notFound = RexLookup.notFound.error ?? .rexNotFound("")
    let busy = actions(busy: [.pane("block:01a1-b"), .session("session:01a1"), .session("session:5c21")], nil)
    try shot("dashboard-sessions-busy", SessionShot(actions: busy))
    try shot("dashboard-sessions-busy-session", SessionShot(open: ["session:01a1"], actions: busy))
    try shot("dashboard-sessions-busy-pane", SessionShot(open: ["session:01a1", "block:01a1-b"], actions: busy))
    let opened = RexActionResult.openedProcessViewer(program: "/opt/homebrew/bin/btop", windowID: "").summary
    try shot("dashboard-sessions-outcome-success", SessionShot(actions: actions(RexActionOutcome(succeeded: true, text: opened))))
    try shot(
        "dashboard-sessions-outcome-not-installed",
        SessionShot(open: ["session:01a1"], actions: actions(RexActionOutcome(succeeded: false, text: RexActionError.actionsNotInstalled.description)))
    )
    try shot(
        "dashboard-sessions-outcome-rex-not-found",
        SessionShot(actions: actions(RexActionOutcome(succeeded: false, text: notFound.description)))
    )
    try shot(
        "dashboard-sessions-unavailable",
        SessionShot(open: ["session:01a1"], actions: .unavailable("Actions on M1 need a Rex host label in Preferences."))
    )
    let pane = Fixtures.sessions.sessions[1].tabs[0].panes[0]
    try renderHosted(
        ClosePaneConfirmation(
            request: PaneCloseRequest(pane: pane, sessionID: "session:01a1", sessionLabel: "computa"),
            onCancel: {}, onConfirm: {}
        ),
        named: "close-pane-confirmation"
    )
}
