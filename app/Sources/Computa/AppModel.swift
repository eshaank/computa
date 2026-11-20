import AppKit
import ComputaCore
import ComputaUI
import Observation
import os

/// Everything the app's scenes share: the daemon connection, Prevent Sleep and the settings.
@MainActor
@Observable
final class AppModel {
    let store: MonitorStore
    let sleep: SleepPreventionModel
    let history: HistoryStore
    let processes: ProcessStore
    let sessions: SessionStore
    @ObservationIgnored private let settings = DaemonAddressSetting(defaults: .standard)
    @ObservationIgnored private let logger = Logger(subsystem: "app.computa.Computa", category: "app")

    init() {
        store = MonitorStore(endpoint: settings.endpoint)
        history = HistoryStore(endpoint: settings.endpoint)
        processes = ProcessStore(endpoint: settings.endpoint)
        sessions = SessionStore(endpoint: settings.endpoint)
        sleep = SleepPreventionModel(preventer: IOKitSleepPreventer())
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
