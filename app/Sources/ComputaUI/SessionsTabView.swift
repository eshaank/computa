import ComputaCore
import SwiftUI

/// What the Sessions tab remembers between updates: the sort and which sessions and panes are
/// open, keyed by Rex's ids. The app owns it so it survives snapshots and tab switches.
public struct SessionsViewState: Sendable, Equatable {
    public var metric: ProcessMetric
    public var expanded: Set<String>

    public init(metric: ProcessMetric = .memory, expanded: Set<String> = []) {
        self.metric = metric
        self.expanded = expanded
    }
}

/// The Sessions tab below the info line: a summary panel where other tabs have the chart, the
/// sort control, and the session list; or a panel saying why there is nothing to show.
struct SessionsTabView: View {
    let state: ConnectionState
    /// Only set while the sessions stream is connected.
    let snapshot: SessionsSnapshot?
    @Binding var view: SessionsViewState

    var body: some View {
        if let snapshot {
            if snapshot.rex.reachable {
                reachable(snapshot)
            } else {
                MessagePanel(
                    symbol: "terminal", tint: Theme.warning, title: "Rex not reachable",
                    lines: [
                        snapshot.rex.problem.isEmpty ? "computad could not reach Rex." : snapshot.rex.problem,
                        "The other tabs still work. This one fills in as soon as Rex answers.",
                    ]
                )
            }
        } else if case .daemonNotRunning(let problem) = state {
            VStack {
                DaemonDownSection(problem: problem)
                Spacer(minLength: 0)
            }
            .background(DashboardPanel())
        } else {
            Text("Loading sessions…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dimText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DashboardPanel())
        }
    }

    @ViewBuilder
    private func reachable(_ snapshot: SessionsSnapshot) -> some View {
        SessionsSummaryPanel(summary: SessionsSummary(snapshot.sessions), version: snapshot.rex.version)
        HStack {
            Text("Sort by")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText)
            Spacer(minLength: 8)
            SegmentedPicker(
                items: [ProcessMetric.memory, .cpu], selection: $view.metric, title: \.title,
                tint: { _ in Theme.sessions }, segmentWidth: 62, height: 22, font: .system(size: 11, weight: .semibold)
            )
        }
        .padding(.leading, 4)
        if snapshot.sessions.isEmpty {
            MessagePanel(
                symbol: "rectangle.stack", tint: Theme.dimText, title: "No Rex sessions",
                lines: ["Sessions you open in Rex show here, with what their panes use."]
            )
        } else {
            SessionListView(
                sessions: SessionList.sorted(snapshot.sessions, by: view.metric),
                metric: view.metric, expanded: $view.expanded
            )
            .clipShape(RoundedRectangle(cornerRadius: DashboardMetrics.panelRadius, style: .continuous))
        }
    }
}

/// A panel with a glyph, a title and a few lines, for the tab's empty and problem states.
struct MessagePanel: View {
    let symbol: String
    let tint: Color
    let title: String
    let lines: [String]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.6), radius: 6)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundStyle(index == 0 ? Theme.text.opacity(0.8) : Theme.dimText)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Metrics.sidePadding)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .background(DashboardPanel())
    }
}
