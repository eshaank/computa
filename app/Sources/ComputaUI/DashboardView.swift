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

/// The dashboard window: the tabs as a segmented control in the toolbar, as in Activity
/// Monitor, the machine in the title, a history chart, and the tab's list below it. The selected tab, range, search text, expanded groups and the Sessions tab's sort
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
            if let tunnel = content.machine.pendingTunnel {
                TunnelStatusView(machine: content.machine, state: tunnel)
                    .background(DashboardPanel())
                Spacer(minLength: 0)
            } else {
                stateBody
            }
        }
        .padding(DashboardMetrics.sidePadding)
        .frame(
            minWidth: DashboardMetrics.minimumSize.width, maxWidth: .infinity,
            minHeight: DashboardMetrics.minimumSize.height, maxHeight: .infinity, alignment: .top
        )
        .background(Theme.background)
        .toolbar {
            DashboardToolbar(tab: $tab, machine: content.machine, switching: machines)
        }
        .navigationTitle(windowTitle)
        .navigationSubtitle(content.host?.chip ?? "")
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    /// The machine's host name, as Activity Monitor names the Mac it watches.
    private var windowTitle: String {
        if content.machine.pendingTunnel == nil, let host = content.host { return host.hostname }
        return content.machine.name
    }

    /// Numbers while connected; otherwise why not.
    @ViewBuilder
    private var stateBody: some View {
        switch content.state {
        case .connected:
            connectedBody
        case .connecting:
            ConnectingPanel(endpoint: content.endpoint, machine: content.machine)
        case .daemonNotRunning(let problem):
            DaemonDownSection(problem: problem)
                .background(DashboardPanel())
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var connectedBody: some View {
        if tab.showsHistory {
            VStack(spacing: 8) {
                ChartHeader(tab: tab, sample: content.sample, range: $range)
                HistoryChartView(model: chartModel, tab: tab, message: chartMessage)
                    .frame(height: DashboardMetrics.chartHeight)
                ChartLegend(entries: tab.legend(content.sample), headline: tab.headline(content.sample))
                if tab == .memory, let memory = content.sample?.memory {
                    MemoryLegendDetail(memory: memory)
                }
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

    @ViewBuilder
    private var tabBody: some View {
        switch tab {
        case .network:
            if let sample = content.sample { NetworkPanel(network: sample.network) }
            processSection(.network)
        case .disk:
            if let sample = content.sample { DiskPanel(sample: sample) }
        case .cpu, .memory, .sessions:
            if let metric = tab.processMetric { processSection(metric) }
        }
    }

    @ViewBuilder
    private func processSection(_ metric: ProcessMetric) -> some View {
        SearchField(text: $query)
        if let snapshot = content.processes {
            ProcessPanel(snapshot: snapshot, metric: metric, query: query, expanded: $expanded, icons: icons)
        } else if case .daemonNotRunning(let problem) = content.processState {
            VStack {
                DaemonDownSection(problem: problem)
                Spacer(minLength: 0)
            }
            .background(DashboardPanel())
        } else {
            ContentUnavailableView {
                ProgressView().controlSize(.small)
            } description: {
                Text("Loading processes…")
            }
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
