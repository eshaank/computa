import AppKit
import ComputaCore
import ComputaUI
import SwiftUI

/// Two machines: This Mac and "M1", reached over SSH. The ids are fixed so the PNGs do not
/// change between runs.
@MainActor
enum MachineFixtures {
    static let m1Remote = RemoteMachine(destination: "morgan@100.64.0.5", rexHost: "m1")
    static let m1 = Machine(id: "m1", name: "M1", kind: .remote(m1Remote))
    static let studio = Machine(id: "studio", name: "Studio", kind: .remote(RemoteMachine(destination: "morgan@studio.netbird.cloud", sshPort: 2222)))
    static let machines: [Machine] = [.thisMac(), m1]

    static func context(selected: String, tunnel: TunnelState? = nil, machines: [Machine] = machines) -> MachineContext {
        MachineContext(list: MachineList(machines: machines, selectedID: selected), tunnel: tunnel)
    }

    static let tunnelEnd = DaemonEndpoint(host: "127.0.0.1", port: 52814)
    static let unreachable = SSHFailure.reason(
        stderr: "ssh: connect to host 100.64.0.5 port 22: Operation timed out", status: 255, machine: m1Remote
    )

    /// The M1's facts, as its daemon would report them.
    static var m1Host: HostInfo {
        var host = Fixtures.host
        host.hostname = "Morgans-Mac-mini"
        host.chip = "Apple M1"
        host.model = "Macmini9,1"
        return host
    }
}

/// The switcher, a remote machine in each tunnel state, Preferences' machine list and form,
/// and the Sessions tab on a remote machine without a Rex host label.
@MainActor
func renderMachines() throws {
    try renderMachinePopovers()
    try renderMachineDashboards()
    try renderMachinePreferences()
}

@MainActor
private func renderMachinePopovers() throws {
    func shot(_ name: String, _ machine: MachineContext, state: ConnectionState = .connected, host: HostInfo? = Fixtures.host) throws {
        let content = PopoverContent(
            state: state, sample: Fixtures.sample, host: host, endpoint: machine.tunnel?.endpoint ?? .local,
            preventSleepOn: false, preventSleepError: nil, machine: machine
        )
        try renderHosted(PopoverView(content: content, actions: .none).environment(\.drawsGlass, false), named: name)
    }
    let m1 = MachineFixtures.m1.id
    try shot("popover-machines-this-mac", MachineFixtures.context(selected: Machine.thisMacID))
    try render(MachineMenuPreview(machine: MachineFixtures.context(selected: Machine.thisMacID)), named: "popover-machines-menu")
    try shot(
        "popover-remote-connected", MachineFixtures.context(selected: m1, tunnel: .connected(MachineFixtures.tunnelEnd)),
        host: MachineFixtures.m1Host
    )
    try shot("popover-remote-connecting", MachineFixtures.context(selected: m1), state: .connecting, host: nil)
    try shot(
        "popover-remote-unreachable", MachineFixtures.context(selected: m1, tunnel: .unreachable(MachineFixtures.unreachable)),
        state: .connecting, host: nil
    )
    let notRunning = MachineFixtures.context(selected: m1, tunnel: .connected(MachineFixtures.tunnelEnd))
        .describe(DaemonProblem(kind: .unreachable, summary: "", detail: "unavailable"))
    try shot(
        "popover-remote-daemon-not-running", MachineFixtures.context(selected: m1, tunnel: .connected(MachineFixtures.tunnelEnd)),
        state: .daemonNotRunning(notRunning), host: nil
    )
}

@MainActor
private func renderMachineDashboards() throws {
    let icons = LocalAppIconProvider()
    let m1 = MachineFixtures.m1.id
    func shot(
        _ name: String, _ machine: MachineContext, tab: DashboardTab = .cpu, state: ConnectionState = .connected,
        actions: SessionActions = .none, height: CGFloat = 760
    ) throws {
        let content = DashboardContent(
            state: state, sample: Fixtures.dashboardSample, host: state.isConnected ? MachineFixtures.m1Host : nil,
            endpoint: MachineFixtures.tunnelEnd, history: Fixtures.history(), historyProblem: nil,
            processState: .connected, processes: Fixtures.processes, sessionsState: .connected, sessions: Fixtures.sessions,
            machine: machine
        )
        let view = DashboardView(
            content: content, tab: .constant(tab), range: .constant(.fifteenMinutes), query: .constant(""),
            expanded: .constant([]), sessionsView: .constant(SessionsViewState(expanded: ["session:01a1"])),
            icons: icons, sessionActions: actions
        )
        try renderWindow(view, size: CGSize(width: dashboardWidth, height: height), named: name)
    }
    let connected = MachineFixtures.context(selected: m1, tunnel: .connected(MachineFixtures.tunnelEnd))
    try shot("dashboard-remote", connected)
    try shot("dashboard-remote-connecting", MachineFixtures.context(selected: m1), state: .connecting, height: 560)
    try shot(
        "dashboard-remote-unreachable", MachineFixtures.context(selected: m1, tunnel: .unreachable(MachineFixtures.unreachable)),
        state: .connecting, height: 560
    )
    let unlabelled = Machine(id: "m1", name: "M1", kind: .remote(RemoteMachine(destination: "morgan@100.64.0.5")))
    try shot(
        "dashboard-sessions-remote-no-label",
        MachineFixtures.context(selected: m1, tunnel: .connected(MachineFixtures.tunnelEnd), machines: [.thisMac(), unlabelled]),
        tab: .sessions, actions: .unavailable("Actions on M1 need a Rex host label in Preferences."), height: 640
    )
}

@MainActor
private func renderMachinePreferences() throws {
    let installed = "/Users/morgan/" + RexLocator.installPath
    let lookup = RexLookup.found(path: installed, source: .installLocation)
    let machines: [Machine] = [.thisMac(), MachineFixtures.m1, MachineFixtures.studio]
    try renderHosted(preferences(rexCommand: "", lookup: lookup, machines: machines), height: preferencesHeight, named: "preferences-machines")
    let draft = MachineDraft(name: "M1", destination: "morgan@100.64.0.5", rexHost: "m1")
    try renderHosted(
        preferences(rexCommand: "", lookup: lookup, machines: [.thisMac()], form: MachineForm(target: .add, draft: draft)),
        height: preferencesHeight, named: "preferences-machine-form"
    )
    var hostile = draft
    hostile.destination = "-oProxyCommand=sh"
    var error: String?
    do {
        var list = MachineList()
        try list.add(hostile)
    } catch let validation {
        error = validation.description
    }
    try renderHosted(
        preferences(
            rexCommand: "", lookup: lookup, machines: [.thisMac()],
            form: MachineForm(target: .add, draft: hostile, error: error)
        ),
        height: preferencesHeight, named: "preferences-machine-form-error"
    )
    try renderHosted(
        preferences(rexCommand: "", lookup: lookup, machines: machines, form: .editing(.thisMac())),
        height: preferencesHeight, named: "preferences-this-mac-form"
    )
}
