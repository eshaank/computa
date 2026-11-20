import AppKit
import ComputaCore
import ComputaUI
import Observation
import os

/// Everything the app's scenes share: the machines and the daemon connection, Prevent Sleep,
/// Rex actions and the settings.
@MainActor
@Observable
final class AppModel {
    let store: MonitorStore
    let sleep: SleepPreventionModel
    let history: HistoryStore
    let processes: ProcessStore
    let sessions: SessionStore
    let machines: MachineController
    @ObservationIgnored let rexSetting: RexCommandSetting
    @ObservationIgnored private let actionModels: RexActionModels
    @ObservationIgnored private let remoteIcons = RemoteIconCache()
    @ObservationIgnored private var iconProviders: [String: RemoteAppIconProvider] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "app.computa.Computa", category: "app")

    init() {
        // Pointed at their machine by the machine controller below.
        store = MonitorStore(endpoint: .local)
        history = HistoryStore(endpoint: .local)
        processes = ProcessStore(endpoint: .local)
        sessions = SessionStore(endpoint: .local)
        sleep = SleepPreventionModel(preventer: IOKitSleepPreventer())
        let rexSetting = RexCommandSetting(defaults: .standard)
        self.rexSetting = rexSetting
        actionModels = RexActionModels(locate: { rexSetting.lookup() })
        machines = MachineController(
            settings: MachineSettings(defaults: .standard),
            stores: MachineStores(monitor: store, history: history, processes: processes, sessions: sessions),
            makeTunnel: { SSHTunnel(machine: $0) }
        )
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationWillTerminate() }
        }
        logger.info("starting; showing \(self.machines.selected.name, privacy: .public)")
        store.start()
    }

    private var machineContext: MachineContext {
        MachineContext(list: machines.list, tunnel: machines.tunnelState)
    }

    var popoverContent: PopoverContent {
        let machine = machineContext
        return PopoverContent(
            state: machine.describe(store.state), sample: store.sample, host: store.host, endpoint: store.endpoint,
            preventSleepOn: sleep.isOn, preventSleepError: sleep.lastError,
            claudeSummary: ClaudeUsage.popoverText(sessions.snapshot), machine: machine
        )
    }

    var dashboardContent: DashboardContent {
        let machine = machineContext
        return DashboardContent(
            state: machine.describe(store.state), sample: store.sample, host: store.host, endpoint: store.endpoint,
            history: history.series, historyProblem: history.problem.map(machine.describe),
            processState: machine.describe(processes.state), processes: processes.snapshot,
            sessionsState: machine.describe(sessions.state), sessions: sessions.snapshot, machine: machine
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

    /// The Sessions tab's action controls, for the shown machine's Rex server. The target is
    /// fixed when an action starts, so switching machines never sends it elsewhere.
    var sessionActions: SessionActions {
        let machine = machines.selected
        guard let model = actionModels.model(for: machine.rexTarget) else {
            return .unavailable("Actions on \(machine.name) need a Rex host label in Preferences.")
        }
        return SessionActions(busy: model.busy, outcome: model.outcome) { [weak model] action in
            model?.run(action)
        }
    }

    /// Icons for the dashboard's process list: from this Mac's disk, or from the remote daemon.
    func iconProvider(local: LocalAppIconProvider) -> any AppIconProviding {
        let machine = machines.selected
        guard machine.remote != nil else { return local }
        if let provider = iconProviders[machine.id] { return provider }
        let provider = RemoteAppIconProvider(cache: remoteIcons, machineID: machine.id) { [weak self] in
            self?.machines.selected.id == machine.id ? self?.machines.tunnelState?.endpoint : nil
        }
        iconProviders[machine.id] = provider
        return provider
    }

    /// Stores the `rex` path (blank: find it automatically) and says where `rex` is now.
    func saveRexCommand(_ text: String) -> RexLookup {
        rexSetting.save(text)
        let lookup = rexSetting.lookup()
        logger.info("rex command set to \"\(text, privacy: .public)\": \(lookup.summary, privacy: .public)")
        return lookup
    }

    var machineEditing: MachineEditing {
        let machines = machines
        return MachineEditing(
            save: { (draft, id) throws(MachineValidationError) in try machines.save(draft, id: id) },
            saveThisMacAddress: { (text) throws(MachineValidationError) in try machines.saveThisMacAddress(text) },
            remove: { (id) throws(MachineValidationError) in try machines.remove(id) }
        )
    }

    private func applicationWillTerminate() {
        logger.info("quitting; releasing prevent-sleep if held, stopping any tunnel")
        sleep.set(on: false)
        machines.stop()
        history.setOpen(false)
        processes.stop()
        sessions.stop()
        store.stop()
    }
}

/// One Rex actions model per Rex server, so each keeps its own busy rows and outcome.
@MainActor
private final class RexActionModels {
    private let locate: @Sendable () -> RexLookup
    private var models: [[String]: RexActionsModel] = [:]

    init(locate: @escaping @Sendable () -> RexLookup) {
        self.locate = locate
    }

    /// Nil when actions cannot run on the target.
    func model(for target: RexTarget) -> RexActionsModel? {
        guard let prefix = target.prefix else { return nil }
        if let model = models[prefix] { return model }
        // Looked up again for every action, so a new setting or a new Rex install counts at once.
        let model = RexActionsModel(runner: ProcessRexRunner(locate: locate, prefix: prefix))
        models[prefix] = model
        return model
    }
}
