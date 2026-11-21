import Foundation
import Testing

@testable import ComputaCore

/// A tunnel the test drives by hand.
@MainActor
final class FakeTunnel: Tunneling {
    let machine: RemoteMachine
    var state: TunnelState = .connecting
    var onStateChange: (@MainActor (TunnelState) -> Void)?
    private(set) var started = false
    private(set) var stopped = false

    init(machine: RemoteMachine) {
        self.machine = machine
    }

    func start() { started = true }
    func stop() { stopped = true }

    func emit(_ newState: TunnelState) {
        state = newState
        onStateChange?(newState)
    }
}

@MainActor
@Suite struct MachineControllerTests {
    let fake = FakeMonitorClient([.sendThenHang([Fixtures.sample])])
    let defaults: UserDefaults
    let thisMac = DaemonEndpoint(host: "127.0.0.1", port: 7399)
    let tunnelEnd = DaemonEndpoint(host: "127.0.0.1", port: 6001)

    init() {
        let name = "computa-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    func stores() -> MachineStores {
        let fake = fake
        let clock = ManualSleep()
        let sleep: @Sendable (Duration) async throws -> Void = { try await clock.sleep($0) }
        return MachineStores(
            monitor: MonitorStore(endpoint: .local, makeClient: { _ in fake }, sleep: sleep),
            history: HistoryStore(endpoint: .local, makeClient: { _ in fake }, sleep: sleep),
            processes: ProcessStore(endpoint: .local, makeClient: { _ in fake }, sleep: sleep),
            sessions: SessionStore(endpoint: .local, makeClient: { _ in fake }, sleep: sleep)
        )
    }

    /// This Mac at `thisMac` and a remote "M1", This Mac selected.
    func setUp() throws -> (MachineController, MachineStores, String, () -> [FakeTunnel]) {
        var list = MachineList(thisMacAddress: thisMac)
        let m1 = try list.add(MachineDraft(name: "M1", destination: "me@m1"))
        try MachineSettings(defaults: defaults).save(list)
        let stores = stores()
        let made = TunnelLog()
        let controller = MachineController(settings: MachineSettings(defaults: defaults), stores: stores) { remote in
            let tunnel = FakeTunnel(machine: remote)
            made.tunnels.append(tunnel)
            return tunnel
        }
        stores.monitor.start()
        stores.processes.setDashboardOpen(true)
        return (controller, stores, m1.id, { made.tunnels })
    }

    @Test func switchingRepointsTheStoresAndClearsThePreviousMachine() async throws {
        let (controller, stores, m1, tunnels) = try setUp()
        #expect(stores.monitor.endpoint == thisMac)
        try await eventually("This Mac connected") { stores.monitor.sample != nil && stores.monitor.host != nil }

        controller.select(m1)
        #expect(tunnels().count == 1)
        #expect(tunnels()[0].started)
        #expect(tunnels()[0].machine.destination == "me@m1")
        #expect(controller.tunnelState == .connecting)
        #expect(stores.monitor.sample == nil, "no stale numbers from This Mac")
        #expect(stores.monitor.host == nil, "no stale hostname from This Mac")
        #expect(stores.processes.snapshot == nil)
        #expect(!stores.processes.isStreaming)
        #expect(stores.monitor.isSuspended && stores.history.isSuspended && stores.sessions.isSuspended)
        #expect(MachineSettings(defaults: defaults).load().selectedID == m1, "the selection is stored")

        tunnels()[0].emit(.connected(tunnelEnd))
        #expect(controller.tunnelState == .connected(tunnelEnd))
        #expect([stores.monitor.endpoint, stores.history.endpoint, stores.processes.endpoint, stores.sessions.endpoint]
            .allSatisfy { $0 == tunnelEnd })
        try await eventually("M1 connected") { stores.monitor.sample != nil && stores.processes.snapshot != nil }

        tunnels()[0].emit(.unreachable("M1 did not answer."))
        #expect(stores.monitor.sample == nil)
        #expect(stores.monitor.isSuspended)

        controller.select(Machine.thisMacID)
        #expect(tunnels()[0].stopped, "switching back to This Mac stops the tunnel")
        #expect(controller.tunnelState == nil)
        #expect(stores.monitor.endpoint == thisMac)
        #expect(!stores.monitor.isSuspended)
        try await eventually("This Mac again") { stores.monitor.sample != nil && stores.processes.isStreaming }
        stores.monitor.stop()
        stores.processes.stop()
    }

    @Test func lateStateChangesFromAStoppedTunnelAreIgnored() throws {
        let (controller, stores, m1, tunnels) = try setUp()
        controller.select(m1)
        controller.select(Machine.thisMacID)
        tunnels()[0].emit(.connected(tunnelEnd))
        #expect(stores.monitor.endpoint == thisMac)
        #expect(controller.tunnelState == nil)
        stores.monitor.stop()
    }

    @Test func removingTheSelectedRemoteMachineStopsItsTunnelAndShowsThisMac() throws {
        let (controller, stores, m1, tunnels) = try setUp()
        controller.select(m1)
        try controller.remove(m1)
        #expect(tunnels()[0].stopped)
        #expect(controller.selected.isThisMac)
        #expect(stores.monitor.endpoint == thisMac)
        #expect(MachineSettings(defaults: defaults).load().machines.count == 1)
        stores.monitor.stop()
    }

    @Test func editingTheSelectedMachineRestartsItsTunnel() throws {
        let (controller, stores, m1, tunnels) = try setUp()
        controller.select(m1)
        try controller.save(MachineDraft(name: "M1", destination: "me@m1.netbird", daemonPort: "7400"), id: m1)
        #expect(tunnels().count == 2)
        #expect(tunnels()[0].stopped)
        #expect(tunnels()[1].machine == RemoteMachine(destination: "me@m1.netbird", daemonPort: 7400))
        #expect(throws: MachineValidationError.emptyName) { try controller.save(MachineDraft(destination: "x"), id: nil) }
        #expect(tunnels().count == 2, "a rejected draft changes nothing")
        try controller.save(MachineDraft(name: "M1 mini", destination: "me@m1.netbird", daemonPort: "7400", rexHost: "m1"), id: m1)
        #expect(tunnels().count == 2, "a new name or Rex label keeps the tunnel")
        #expect(controller.selected.rexTarget == .host("m1"))
        controller.stop()
        stores.monitor.stop()
    }

    @Test func launchingWithARemoteMachineSelectedWaitsForItsTunnel() async throws {
        var list = MachineList(thisMacAddress: thisMac)
        let m1 = try list.add(MachineDraft(name: "M1", destination: "me@m1"))
        try list.select(m1.id)
        try MachineSettings(defaults: defaults).save(list)
        let stores = stores()
        let made = TunnelLog()
        let controller = MachineController(settings: MachineSettings(defaults: defaults), stores: stores) { remote in
            let tunnel = FakeTunnel(machine: remote)
            made.tunnels.append(tunnel)
            return tunnel
        }
        stores.monitor.start()
        #expect(controller.selected.id == m1.id)
        #expect(made.tunnels.count == 1 && made.tunnels[0].started)
        try await pause(for: .milliseconds(50))
        #expect(fake.attempts == 0, "nothing is asked before the tunnel is up")
        made.tunnels[0].emit(.connected(tunnelEnd))
        try await eventually("connected through the tunnel") { stores.monitor.sample != nil }
        #expect(stores.monitor.endpoint == tunnelEnd)
        controller.stop()
        stores.monitor.stop()
    }

    @Test func savingThisMacsAddressRepointsTheStoresWhileItIsShown() throws {
        let (controller, stores, _, _) = try setUp()
        let address = try controller.saveThisMacAddress("127.0.0.1:7398")
        #expect(stores.monitor.endpoint == address)
        #expect(stores.history.endpoint == address)
        stores.monitor.stop()
    }

    @Test func remoteProblemsNameTheMachineNotTheTunnelPort() throws {
        var list = MachineList()
        let m1 = try list.add(MachineDraft(name: "M1", destination: "me@m1"))
        try list.select(m1.id)
        let context = MachineContext(list: list, tunnel: .connected(tunnelEnd))
        let problem = DaemonProblem(error: unavailable, endpoint: tunnelEnd)
        #expect(problem.summary.contains("6001"))
        #expect(context.describe(problem).summary == "computad is not answering on M1. Check that it is installed and running there.")
        #expect(context.pendingTunnel == nil)
        #expect(MachineContext(list: list, tunnel: .unreachable("x")).pendingTunnel == .unreachable("x"))
        #expect(MachineContext.thisMacOnly.describe(problem) == problem)
        #expect(!MachineContext.thisMacOnly.showsSwitcher)
        #expect(context.showsSwitcher)
    }
}

@MainActor
private final class TunnelLog {
    var tunnels: [FakeTunnel] = []
}
