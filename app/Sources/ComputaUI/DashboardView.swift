import ComputaCore
import SwiftUI

/// Everything the dashboard shows, as plain values.
public struct DashboardContent: Sendable, Equatable {
    /// The live connection, which decides between numbers, "connecting" and "not running".
    public var state: ConnectionState
    /// The live sample; only kept while connected.
    public var sample: SystemSample?
    public var host: HostInfo?
    public var endpoint: DaemonEndpoint
    public var history: HistorySeries?
    public var historyProblem: DaemonProblem?
    public var processState: ConnectionState
    /// Only kept while the process stream is connected.
    public var processes: ProcessSnapshot?
    public var sessionsState: ConnectionState
    /// Only kept while the sessions stream is connected.
    public var sessions: SessionsSnapshot?

    public init(
        state: ConnectionState, sample: SystemSample?, host: HostInfo?, endpoint: DaemonEndpoint,
        history: HistorySeries?, historyProblem: DaemonProblem?,
        processState: ConnectionState, processes: ProcessSnapshot?,
        sessionsState: ConnectionState = .connecting, sessions: SessionsSnapshot? = nil
    ) {
        self.state = state
        self.sample = state.isConnected ? sample : nil
        self.host = host
        self.endpoint = endpoint
        self.history = history
        self.historyProblem = historyProblem
        self.processState = processState
        self.processes = processState.isConnected ? processes : nil
        self.sessionsState = sessionsState
        self.sessions = sessionsState.isConnected ? sessions : nil
    }
}

/// The dashboard window: tabs, a history chart, and the tab's list below it, laid out like the
/// reference. The selected tab, range, search text, expanded groups and the Sessions tab's sort
/// and open rows are bindings, so the app owns them and snapshots can set them.
public struct DashboardView: View {
    let content: DashboardContent
    @Binding var tab: DashboardTab
    @Binding var range: HistoryRange
    @Binding var query: String
    @Binding var expanded: Set<String>
    @Binding var sessionsView: SessionsViewState
    let icons: any AppIconProviding
    let sessionActions: SessionActions

    public init(
        content: DashboardContent, tab: Binding<DashboardTab>, range: Binding<HistoryRange>,
        query: Binding<String>, expanded: Binding<Set<String>>, sessionsView: Binding<SessionsViewState>,
        icons: any AppIconProviding, sessionActions: SessionActions = .none
    ) {
        self.content = content
        _tab = tab
        _range = range
        _query = query
        _expanded = expanded
        _sessionsView = sessionsView
        self.icons = icons
        self.sessionActions = sessionActions
    }

    public var body: some View {
        VStack(spacing: 12) {
            DashboardTabBar(tab: $tab)
                .padding(.top, 14)
            switch content.state {
            case .connected:
                connectedBody
            case .connecting:
                ConnectingPanel(endpoint: content.endpoint)
                Spacer(minLength: 0)
            case .daemonNotRunning(let problem):
                DaemonDownSection(problem: problem)
                    .background(DashboardPanel())
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DashboardMetrics.sidePadding)
        .padding(.bottom, DashboardMetrics.sidePadding)
        .frame(
            minWidth: DashboardMetrics.minimumSize.width, maxWidth: .infinity,
            minHeight: DashboardMetrics.minimumSize.height, maxHeight: .infinity, alignment: .top
        )
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var connectedBody: some View {
        infoLine
        if tab.showsHistory {
            VStack(spacing: 8) {
                HistoryChartView(model: chartModel, tab: tab, message: chartMessage)
                    .frame(height: DashboardMetrics.chartHeight)
                ChartLegend(entries: tab.legend(content.sample), headline: tab.headline(content.sample))
            }
            tabBody
        } else {
            SessionsTabView(
                state: content.sessionsState, snapshot: content.sessions, view: $sessionsView, actions: sessionActions
            )
        }
    }

    /// The machine on the left, the range picker on the right.
    private var infoLine: some View {
        HStack(spacing: 8) {
            if let host = content.host {
                Text(host.hostname)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(host.chip)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dimText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            // Hidden rather than removed on the Sessions tab, so the line keeps its height.
            RangePicker(range: $range, tint: tab.color)
                .opacity(tab.showsHistory ? 1 : 0)
                .allowsHitTesting(tab.showsHistory)
                .accessibilityHidden(!tab.showsHistory)
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        if let metric = tab.processMetric {
            SearchField(text: $query)
            processPanel(metric)
        } else if let sample = content.sample {
            if tab == .network { NetworkPanel(network: sample.network) } else { DiskPanel(sample: sample) }
        }
    }

    @ViewBuilder
    private func processPanel(_ metric: ProcessMetric) -> some View {
        if let snapshot = content.processes {
            ProcessListView(
                groups: ProcessList.visible(snapshot.groups, query: query, metric: metric),
                metric: metric,
                hidden: metric == .memory && query.trimmingCharacters(in: .whitespaces).isEmpty ? snapshot.hidden : nil,
                expanded: $expanded,
                icons: icons
            )
            .clipShape(RoundedRectangle(cornerRadius: DashboardMetrics.panelRadius, style: .continuous))
        } else if case .daemonNotRunning(let problem) = content.processState {
            VStack {
                DaemonDownSection(problem: problem)
                Spacer(minLength: 0)
            }
            .background(DashboardPanel())
        } else {
            Text("Loading processes…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dimText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DashboardPanel())
        }
    }

    private var chartModel: ChartModel {
        ChartBuilder.model(
            for: tab, points: content.history?.points ?? [],
            memoryTotal: content.sample?.memory.totalBytes ?? content.host?.memoryTotalBytes ?? 0,
            slotCount: Int(HistoryStore.maxPoints)
        )
    }

    private var chartMessage: String {
        if let problem = content.historyProblem {
            return problem.kind == .unsupported ? "The daemon needs an update to show history." : problem.summary
        }
        return content.history == nil ? "Loading history…" : "No history yet."
    }
}

/// Colour keys for the chart's parts with their live values, and the tab's headline number.
struct ChartLegend: View {
    let entries: [LegendEntry]
    let headline: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(entries) { entry in
                HStack(spacing: 5) {
                    Circle().fill(entry.color).frame(width: 7, height: 7)
                    Text(entry.label).foregroundStyle(Theme.dimText)
                    Text(entry.value).foregroundStyle(Theme.text.opacity(0.85))
                }
            }
            Spacer(minLength: 4)
            Text(headline)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.text)
        }
        .font(.system(size: 11).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, 4)
    }
}

/// Shown below the tabs until the first sample arrives.
struct ConnectingPanel: View {
    let endpoint: DaemonEndpoint

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.dimText)
            Text("Connecting…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Waiting for computad at \(endpoint.description).")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(DashboardPanel())
    }
}
