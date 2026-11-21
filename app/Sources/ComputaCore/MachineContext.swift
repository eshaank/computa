import Foundation

/// What the popover and dashboard show about machines, as plain values: the switcher's
/// choices, the selected machine, and its tunnel.
public struct MachineContext: Sendable, Equatable {
    public struct Choice: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public var choices: [Choice]
    public var selectedID: String
    /// The selected machine's name.
    public var name: String
    /// The selected machine's settings when it is remote.
    public var remote: RemoteMachine?
    /// The selected remote machine's tunnel.
    public var tunnel: TunnelState?

    public init(
        choices: [Choice], selectedID: String, name: String, remote: RemoteMachine? = nil, tunnel: TunnelState? = nil
    ) {
        self.choices = choices
        self.selectedID = selectedID
        self.name = name
        self.remote = remote
        self.tunnel = remote == nil ? nil : (tunnel ?? .connecting)
    }

    public init(list: MachineList, tunnel: TunnelState?) {
        self.init(
            choices: list.machines.map { Choice(id: $0.id, name: $0.name) }, selectedID: list.selectedID,
            name: list.selected.name, remote: list.selected.remote, tunnel: tunnel
        )
    }

    /// Only This Mac: everything looks as it did before machines existed.
    public static let thisMacOnly = MachineContext(
        choices: [Choice(id: Machine.thisMacID, name: Machine.thisMacName)], selectedID: Machine.thisMacID,
        name: Machine.thisMacName
    )

    public var showsSwitcher: Bool { choices.count > 1 }
    public var isRemote: Bool { remote != nil }

    /// The tunnel's state while it stands between the app and the numbers: a remote machine
    /// whose tunnel is not connected. The UI shows this instead of the daemon's state.
    public var pendingTunnel: TunnelState? {
        guard let tunnel, tunnel.endpoint == nil else { return nil }
        return tunnel
    }

    /// Words a daemon problem for the selected machine. A remote daemon is reached through a
    /// local port that means nothing to the owner, so its sentences name the machine instead.
    public func describe(_ problem: DaemonProblem) -> DaemonProblem {
        guard isRemote else { return problem }
        var described = problem
        described.summary = switch problem.kind {
        case .unreachable: "computad is not answering on \(name). Check that it is installed and running there."
        case .unsupported: "computad on \(name) does not offer this call yet. Update the daemon there."
        case .streamEnded: "computad on \(name) stopped sending samples."
        case .other: "computad on \(name) reported an error."
        }
        return described
    }

    public func describe(_ state: ConnectionState) -> ConnectionState {
        if case .daemonNotRunning(let problem) = state { .daemonNotRunning(describe(problem)) } else { state }
    }
}
