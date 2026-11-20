import Foundation
import Observation
import os

/// The stores that talk to the selected machine's daemon.
@MainActor
public struct MachineStores {
    public let monitor: MonitorStore
    public let history: HistoryStore
    public let processes: ProcessStore
    public let sessions: SessionStore

    public init(monitor: MonitorStore, history: HistoryStore, processes: ProcessStore, sessions: SessionStore) {
        self.monitor = monitor
        self.history = history
        self.processes = processes
        self.sessions = sessions
    }

    /// Points every store at a daemon and lets them stream.
    func point(at endpoint: DaemonEndpoint) {
        monitor.setEndpoint(endpoint)
        history.setEndpoint(endpoint)
        processes.setEndpoint(endpoint)
        sessions.setEndpoint(endpoint)
        setSuspended(false)
    }

    /// No daemon to reach: every store stops and drops what it showed.
    func setSuspended(_ suspended: Bool) {
        monitor.setSuspended(suspended)
        history.setSuspended(suspended)
        processes.setSuspended(suspended)
        sessions.setSuspended(suspended)
    }
}

/// The machine list, the selected machine, and its route: This Mac's address directly, or a
/// remote machine's tunnel, which runs only while that machine is selected. Every change of
/// route re-points the stores.
@MainActor
@Observable
public final class MachineController {
    public private(set) var list: MachineList
    /// The selected remote machine's tunnel; nil while This Mac is selected.
    public private(set) var tunnelState: TunnelState?
    /// Why the list could not be stored, if the last save failed.
    public private(set) var saveProblem: String?

    public var selected: Machine { list.selected }

    @ObservationIgnored private let stores: MachineStores
    @ObservationIgnored private let settings: MachineSettings
    @ObservationIgnored private let makeTunnel: TunnelFactory
    @ObservationIgnored private var tunnel: (any Tunneling)?
    @ObservationIgnored private let logger = Logger(subsystem: "app.computa.Computa", category: "machines")

    /// Loads the stored list and routes the stores to the selected machine.
    ///
    /// - Parameter makeTunnel: Makes a remote machine's tunnel. Tests pass a fake.
    public init(settings: MachineSettings, stores: MachineStores, makeTunnel: @escaping TunnelFactory) {
        self.settings = settings
        self.stores = stores
        self.makeTunnel = makeTunnel
        list = settings.load()
        route()
    }

    /// Shows another machine. Selecting the shown one again does nothing.
    public func select(_ id: String) {
        guard id != list.selectedID else { return }
        do {
            try list.select(id)
        } catch {
            logger.error("cannot select machine: \(error.description, privacy: .public)")
            return
        }
        logger.info("selected \(self.selected.name, privacy: .public)")
        persist()
        route()
    }

    /// Adds a remote machine (`id` nil) or replaces one's settings.
    @discardableResult
    public func save(_ draft: MachineDraft, id: String?) throws(MachineValidationError) -> Machine {
        let before = id.flatMap { list.machine($0)?.remote }
        let machine = if let id { try list.update(id, with: draft) } else { try list.add(draft) }
        logger.info("saved machine \(machine.name, privacy: .public)")
        persist()
        // A new name or Rex label keeps the tunnel; a new destination or port restarts it.
        if machine.id == list.selectedID, !Self.sameRoute(before, machine.remote) { route() }
        return machine
    }

    /// Checks and stores This Mac's daemon address.
    @discardableResult
    public func saveThisMacAddress(_ text: String) throws(MachineValidationError) -> DaemonEndpoint {
        let address = try list.setThisMacAddress(text)
        logger.info("This Mac's daemon address set to \(address, privacy: .public)")
        persist()
        if selected.isThisMac { route() }
        return address
    }

    /// Removes a remote machine; removing the shown one shows This Mac.
    public func remove(_ id: String) throws(MachineValidationError) {
        let wasSelected = id == list.selectedID
        try list.remove(id)
        logger.info("removed machine \(id, privacy: .public)")
        persist()
        if wasSelected { route() }
    }

    /// Stops the tunnel and waits briefly for ssh to exit. For quitting.
    public func stop() {
        if let ssh = tunnel as? SSHTunnel { ssh.stopNow() } else { tunnel?.stop() }
        tunnel = nil
    }

    // MARK: - Routing

    private static func sameRoute(_ old: RemoteMachine?, _ new: RemoteMachine?) -> Bool {
        guard var old, let new else { return false }
        old.rexHost = new.rexHost
        return old == new
    }

    private func route() {
        tunnel?.stop()
        tunnel = nil
        let machine = selected
        switch machine.kind {
        case .thisMac(let address):
            tunnelState = nil
            stores.point(at: address)
        case .remote(let remote):
            stores.setSuspended(true)
            let newTunnel = makeTunnel(remote)
            tunnel = newTunnel
            tunnelState = newTunnel.state
            newTunnel.onStateChange = { [weak self, weak newTunnel] state in
                guard let self, let newTunnel, self.tunnel === newTunnel else { return }
                self.tunnelChanged(state)
            }
            newTunnel.start()
        }
    }

    private func tunnelChanged(_ state: TunnelState) {
        tunnelState = state
        if let endpoint = state.endpoint {
            logger.info("\(self.selected.name, privacy: .public) reachable through 127.0.0.1:\(endpoint.port)")
            stores.point(at: endpoint)
        } else {
            stores.setSuspended(true)
        }
    }

    private func persist() {
        do {
            try settings.save(list)
            saveProblem = nil
        } catch {
            saveProblem = "Could not store the machine list: \(error.localizedDescription)"
        }
    }
}
