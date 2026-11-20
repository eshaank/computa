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
    /// The machines, the shown one and its tunnel.
    public var machine: MachineContext

    public init(
        state: ConnectionState, sample: SystemSample?, host: HostInfo?, endpoint: DaemonEndpoint,
        history: HistorySeries?, historyProblem: DaemonProblem?,
        processState: ConnectionState, processes: ProcessSnapshot?,
        sessionsState: ConnectionState = .connecting, sessions: SessionsSnapshot? = nil,
        machine: MachineContext = .thisMacOnly
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
        self.machine = machine
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
    let machines: MachineSwitching

    public init(
        content: DashboardContent, tab: Binding<DashboardTab>, range: Binding<HistoryRange>,
        query: Binding<String>, expanded: Binding<Set<String>>, sessionsView: Binding<SessionsViewState>,
        icons: any AppIconProviding, sessionActions: SessionActions = .none, machines: MachineSwitching = .none
    ) {
        self.content = content
        _tab = tab
        _range = range
        _query = query
        _expanded = expanded
        _sessionsView = sessionsView
        self.icons = icons
        self.sessionActions = sessionActions
        self.machines = machines
    }

    public var body: some View {
        VStack(spacing: 12) {
            DashboardTabBar(tab: $tab)
                .padding(.top, 14)
            if let tunnel = content.machine.pendingTunnel {
                infoLine
                TunnelStatusView(machine: content.machine, state: tunnel)
                    .background(DashboardPanel())
                Spacer(minLength: 0)
            } else {
                stateBody
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

    /// Numbers while connected; otherwise why not. The host line stays when there is a machine
    /// to switch to.
    @ViewBuilder
    private var stateBody: some View {
        switch content.state {
        case .connected:
            connectedBody
        case .connecting:
            if content.machine.showsSwitcher { infoLine }
            ConnectingPanel(endpoint: content.endpoint, machine: content.machine)
            Spacer(minLength: 0)
        case .daemonNotRunning(let problem):
            if content.machine.showsSwitcher { infoLine }
            DaemonDownSection(problem: problem)
                .background(DashboardPanel())
            Spacer(minLength: 0)
        }
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
            // A close confirmation belongs to the machine it was asked on; a switch drops it.
            .id(content.machine.selectedID)
        }
    }

    /// The machine on the left (a menu when there are several), the range picker on the right.
    private var infoLine: some View {
        let showsRange = tab.showsHistory && content.state.isConnected && content.machine.pendingTunnel == nil
        return HStack(spacing: 8) {
            if content.machine.showsSwitcher {
                MachineMenu(machine: content.machine, switching: machines) {
                    HStack(spacing: 8) {
                        MachineTitle(name: content.machine.name, font: .system(size: 12, weight: .semibold))
                        hostText
                    }
                }
            } else {
                hostText
            }
            Spacer(minLength: 8)
            // Hidden rather than removed on the Sessions tab, so the line keeps its height.
            RangePicker(range: $range, tint: tab.color)
                .opacity(showsRange ? 1 : 0)
                .allowsHitTesting(showsRange)
                .accessibilityHidden(!showsRange)
        }
    }

    /// The daemon's host name and chip; with several machines the name is dim, after the menu.
    @ViewBuilder
    private var hostText: some View {
        if let host = content.host {
            Text(host.hostname)
                .font(.system(size: content.machine.showsSwitcher ? 11 : 12, weight: content.machine.showsSwitcher ? .regular : .semibold))
                .foregroundStyle(content.machine.showsSwitcher ? Theme.dimText : Theme.text)
                .lineLimit(1)
            Text(host.chip)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText)
                .lineLimit(1)
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
