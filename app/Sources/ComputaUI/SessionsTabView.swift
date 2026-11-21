import ComputaCore
import SwiftUI

/// What the Sessions tab remembers between updates: the sort and where the drill-in is. The app
/// owns it so it survives snapshots and tab switches.
public struct SessionsViewState: Sendable, Equatable {
    public var metric: ProcessMetric
    /// The open path, as Rex ids: empty for every session, a session's id to show its panes, and
    /// that plus one of its panes' ids to show the pane's processes. Ids are stable, so the place
    /// survives every snapshot; see `SessionNavigation.place`. Emptying it goes back to the top.
    public var expanded: Set<String>

    public init(metric: ProcessMetric = .memory, expanded: Set<String> = []) {
        self.metric = metric
        self.expanded = expanded
    }
}

/// The Sessions tab below the info line: the summary panel where other tabs have the chart, the
/// path and sort row, and then the session cards, one session's panes, or one pane's processes.
/// Or a screen saying why there is nothing to show.
struct SessionsTabView: View {
    let state: ConnectionState
    /// Only set while the sessions stream is connected.
    let snapshot: SessionsSnapshot?
    @Binding var view: SessionsViewState
    let actions: SessionActions
    /// A pane waiting for the user to confirm closing it.
    @State private var pendingClose: PaneCloseRequest?
    /// Which way the last move went, so the push slides the right way.
    @State private var forward = true

    var body: some View {
        if let snapshot {
            if snapshot.rex.reachable {
                reachable(snapshot)
            } else {
                SessionStateView(screen: .rexUnreachable(problem: snapshot.rex.problem))
            }
        } else if case .daemonNotRunning(let problem) = state {
            SessionStateView(screen: .daemon(problem))
        } else {
            SessionStateView(screen: .loading)
        }
    }

    private func reachable(_ snapshot: SessionsSnapshot) -> some View {
        let sessions = SessionList.sorted(snapshot.sessions, by: view.metric)
        let summary = SessionsSummary(snapshot.sessions)
        let place = SessionNavigation.place(open: view.expanded, in: sessions)
        return VStack(alignment: .leading, spacing: 12) {
            SessionsSummaryPanel(summary: summary, version: snapshot.rex.version, highlighted: place.session?.id)
            SessionsToolbar(place: place, metric: $view.metric, go: go)
            if let note = actions.unavailableNote {
                ActionsUnavailableLine(note: note)
            }
            Group {
                if sessions.isEmpty {
                    SessionStateView(screen: .noSessions)
                } else {
                    content(place, sessions: sessions, summary: summary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottom) { outcome }
        }
        .sheet(item: $pendingClose) { request in
            ClosePaneConfirmation(
                request: request,
                onCancel: { pendingClose = nil },
                onConfirm: {
                    pendingClose = nil
                    actions.perform(request.action)
                }
            )
        }
    }

    /// The level shown, sliding in from the right going deeper and from the left going back.
    private func content(_ place: SessionPlace, sessions: [RexSession], summary: SessionsSummary) -> some View {
        ZStack {
            switch place {
            case .overview:
                SessionCardGrid(
                    sessions: sessions, summary: summary, metric: view.metric, actions: actions,
                    open: { go(.session($0)) }
                )
                .transition(.push(from: forward ? .trailing : .leading))
            case .session(let session):
                SessionDetailView(
                    session: session, metric: view.metric, actions: actions,
                    openPane: { move(to: SessionNavigation.path(to: $0, in: session)) },
                    requestClose: { pendingClose = $0 }
                )
                .id(session.id)
                .transition(.push(from: forward ? .trailing : .leading))
            case .pane(let pane, let tab, let session):
                PaneDetailView(
                    pane: pane, tab: tab, session: session, metric: view.metric, actions: actions,
                    requestClose: { pendingClose = $0 }
                )
                .id(pane.id)
                .transition(.push(from: forward ? .trailing : .leading))
            }
        }
        .clipped()
    }

    /// The last action's outcome, floating at the foot of the tab so the content never moves.
    @ViewBuilder
    private var outcome: some View {
        if let outcome = actions.outcome {
            ActionOutcomeLine(outcome: outcome)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Solid under the glass, so the text stays readable over the cards.
                .background(
                    Theme.background.opacity(0.9),
                    in: RoundedRectangle(cornerRadius: SessionMetrics.cardRadius, style: .continuous)
                )
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: SessionMetrics.cardRadius, style: .continuous))
                .padding(8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Moves to `place`. Only the ids are kept, so the next snapshot's numbers show there.
    private func go(_ place: SessionPlace) {
        switch place {
        case .overview: move(to: [])
        case .session(let session): move(to: SessionNavigation.path(to: session))
        case .pane(let pane, _, let session): move(to: SessionNavigation.path(to: pane, in: session))
        }
    }

    private func move(to path: Set<String>) {
        forward = path.count > view.expanded.count
        withAnimation(.snappy(duration: 0.28)) { view.expanded = path }
    }
}
