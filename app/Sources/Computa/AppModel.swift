import AppKit
import ComputaCore
import ComputaUI
import Observation
import os

/// Everything the app's scenes share: the daemon connection, Prevent Sleep, Rex actions and the
/// settings.
@MainActor
@Observable
final class AppModel {
    let store: MonitorStore
    let sleep: SleepPreventionModel
    let history: HistoryStore
    let processes: ProcessStore
    let sessions: SessionStore
    let actions: RexActionsModel
    @ObservationIgnored private let settings = DaemonAddressSetting(defaults: .standard)
    @ObservationIgnored let rexSetting: RexCommandSetting
    @ObservationIgnored private let logger = Logger(subsystem: "app.computa.Computa", category: "app")

    init() {
        store = MonitorStore(endpoint: settings.endpoint)
        history = HistoryStore(endpoint: settings.endpoint)
        processes = ProcessStore(endpoint: settings.endpoint)
        sessions = SessionStore(endpoint: settings.endpoint)
        sleep = SleepPreventionModel(preventer: IOKitSleepPreventer())
        let rexSetting = RexCommandSetting(defaults: .standard)
        self.rexSetting = rexSetting
        // Looked up again for every action, so a new setting or a new Rex install counts at once.
        actions = RexActionsModel(runner: ProcessRexRunner(locate: { rexSetting.lookup() }))
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationWillTerminate() }
        }
        logger.info("starting; daemon at \(self.store.endpoint, privacy: .public)")
        store.start()
    }

    var popoverContent: PopoverContent {
        PopoverContent(
            state: store.state, sample: store.sample, host: store.host, endpoint: store.endpoint,
            preventSleepOn: sleep.isOn, preventSleepError: sleep.lastError,
            claudeSummary: ClaudeUsage.popoverText(sessions.snapshot)
        )
    }

    var dashboardContent: DashboardContent {
        DashboardContent(
            state: store.state, sample: store.sample, host: store.host, endpoint: store.endpoint,
            history: history.series, historyProblem: history.problem,
            processState: processes.state, processes: processes.snapshot,
            sessionsState: sessions.state, sessions: sessions.snapshot
        )
    }

    /// The dashboard window opened or closed. History, processes and sessions are only fetched
    /// while it is open; the process and session stores also check which tab shows.
    func setDashboardOpen(_ open: Bool) {
        store.setOpen(open, .dashboard)
        history.setOpen(open)
        processes.setDashboardOpen(open)
        sessions.setDashboardOpen(open)
    }

    /// The dashboard switched tabs.
    func setDashboardTab(_ tab: DashboardTab) {
        processes.setTab(tab)
        sessions.setTab(tab)
    }

    /// The popover opened or closed. Sessions stream while it is open, for its Claude row.
    func setPopoverOpen(_ open: Bool) {
        store.setOpen(open, .popover)
        sessions.setPopoverOpen(open)
    }

    /// The Sessions tab's action controls.
    var sessionActions: SessionActions {
        SessionActions(busy: actions.busy, outcome: actions.outcome) { [weak self] action in
            self?.actions.run(action)
        }
    }

    /// Stores the `rex` path (blank: find it automatically) and says where `rex` is now.
    func saveRexCommand(_ text: String) -> RexLookup {
        rexSetting.save(text)
        let lookup = rexSetting.lookup()
        logger.info("rex command set to \"\(text, privacy: .public)\": \(lookup.summary, privacy: .public)")
        return lookup
    }

    /// Checks, stores and applies a new daemon address.
    func saveAddress(_ text: String) throws(DaemonEndpointError) -> DaemonEndpoint {
        let endpoint = try settings.save(text)
        store.setEndpoint(endpoint)
        history.setEndpoint(endpoint)
        processes.setEndpoint(endpoint)
        sessions.setEndpoint(endpoint)
        return endpoint
    }

    private func applicationWillTerminate() {
        logger.info("quitting; releasing prevent-sleep if held")
        sleep.set(on: false)
        history.setOpen(false)
        processes.stop()
        sessions.stop()
        store.stop()
    }
}
