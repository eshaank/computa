import ComputaCore
import SwiftUI

/// Everything the popover shows, as plain values.
public struct PopoverContent: Sendable, Equatable {
    public var state: ConnectionState
    /// The live sample. The store only provides one while connected.
    public var sample: SystemSample?
    public var host: HostInfo?
    public var endpoint: DaemonEndpoint
    public var preventSleepOn: Bool
    public var preventSleepError: String?
    /// The "Claude Code" row's value, for example "3 panes · 4.2 GB" (`ClaudeUsage.popoverText`).
    /// Nil hides the row.
    public var claudeSummary: String?
    /// The machines, the shown one and its tunnel.
    public var machine: MachineContext

    public init(
        state: ConnectionState, sample: SystemSample?, host: HostInfo?, endpoint: DaemonEndpoint,
        preventSleepOn: Bool, preventSleepError: String?, claudeSummary: String? = nil,
        machine: MachineContext = .thisMacOnly
    ) {
        self.state = state
        self.sample = state.isConnected ? sample : nil
        self.host = host
        self.endpoint = endpoint
        self.preventSleepOn = preventSleepOn
        self.preventSleepError = preventSleepError
        self.claudeSummary = claudeSummary
        self.machine = machine
    }

    /// Under "Claude Code": which memory figure the row's size is. `ClaudeUsage.popoverText`
    /// adds up the panes' `memoryBytes`, which are footprints; change this with it.
    static let claudeMemoryNote = "Footprint of its panes"
    static let claudeMemoryHelp = "Footprint: everything the panes' processes have allocated, compressed and swapped memory included. It is the Footprint column on the Mem tab, not Mem (in RAM)."

    /// Prevent Sleep's subtitle: it always acts on the Mac running the app.
    var preventSleepNote: String? {
        machine.isRemote ? "Keeps this Mac awake" : nil
    }
}

/// What the popover's controls do.
public struct PopoverActions: Sendable {
    public var setPreventSleep: @MainActor @Sendable (Bool) -> Void
    public var openDashboard: @MainActor @Sendable () -> Void
    public var openPreferences: @MainActor @Sendable () -> Void
    public var quit: @MainActor @Sendable () -> Void
    public var machines: MachineSwitching

    public init(
        setPreventSleep: @escaping @MainActor @Sendable (Bool) -> Void,
        openDashboard: @escaping @MainActor @Sendable () -> Void,
        openPreferences: @escaping @MainActor @Sendable () -> Void,
        quit: @escaping @MainActor @Sendable () -> Void,
        machines: MachineSwitching = .none
    ) {
        self.setPreventSleep = setPreventSleep
        self.openDashboard = openDashboard
        self.openPreferences = openPreferences
        self.quit = quit
        self.machines = machines
    }

    /// Does nothing; for previews and snapshots.
    public static let none = PopoverActions(setPreventSleep: { _ in }, openDashboard: {}, openPreferences: {}, quit: {})
}

/// The popover under the menu bar item: a Liquid Glass panel with rings, rows and Prevent
/// Sleep, and glass buttons below it, as in the reference.
public struct PopoverView: View {
    let content: PopoverContent
    let actions: PopoverActions

    public init(content: PopoverContent, actions: PopoverActions) {
        self.content = content
        self.actions = actions
    }

    @Environment(\.drawsGlass) private var drawsGlass

    public var body: some View {
        Group {
            if drawsGlass {
                GlassEffectContainer(spacing: Metrics.gapToCapsule) { stack }
            } else {
                stack
            }
        }
        .frame(width: Metrics.popoverWidth)
        .environment(\.colorScheme, .dark)
    }

    private var stack: some View {
        VStack(spacing: Metrics.gapToCapsule) {
            panel
            buttons
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            numbers
            SectionDivider()
            ToggleRow(
                label: "Prevent Sleep",
                isOn: content.preventSleepOn,
                detail: content.preventSleepNote,
                message: content.preventSleepError,
                onChange: actions.setPreventSleep
            )
            .padding(.horizontal, Metrics.sidePadding)
            .padding(.vertical, 8)
        }
        .popoverGlass(drawsGlass)
    }

    /// Rings and rows; or why there are none: the tunnel is down, or the daemon does not
    /// answer. With more than one machine, the switcher stays at the top in every state.
    @ViewBuilder
    private var numbers: some View {
        let machine = content.machine
        if case .unreachable = machine.pendingTunnel {
            switcherRow(detail: machine.remote?.destination ?? "")
            SectionDivider()
            TunnelStatusView(machine: machine, state: machine.pendingTunnel ?? .connecting)
        } else if case .daemonNotRunning(let problem) = content.state {
            if machine.showsSwitcher {
                switcherRow(detail: "computad not answering")
                SectionDivider()
            }
            DaemonDownSection(problem: problem)
        } else {
            RingsSection(sample: content.sample)
            SectionDivider()
            StatusRows(content: content, switching: actions.machines)
        }
    }

    private func switcherRow(detail: String) -> some View {
        MachineSwitcherRow(machine: content.machine, value: nil, detail: detail, switching: actions.machines)
            .padding(.horizontal, Metrics.sidePadding)
            .padding(.vertical, 6)
    }

    /// Open Dashboard, then Preferences and Quit, as glass buttons.
    private var buttons: some View {
        VStack(spacing: 8) {
            Button { actions.openDashboard() } label: {
                Label("Open Dashboard", systemImage: "chart.bar.xaxis")
                    .frame(maxWidth: .infinity)
            }
            .popoverButtonStyle(drawsGlass, prominent: true)
            .tint(Theme.accent.opacity(0.75))
            HStack(spacing: 8) {
                Button { actions.openPreferences() } label: {
                    Text("Preferences…").frame(maxWidth: .infinity)
                }
                Button { actions.quit() } label: {
                    Text("Quit").frame(maxWidth: .infinity)
                }
            }
            .popoverButtonStyle(drawsGlass, prominent: false)
        }
        .controlSize(.large)
    }
}

/// The popover's glass: tinted toward the theme's background so white text stays readable
/// over a bright desktop.
enum PopoverGlass {
    static let panel = Glass.regular.tint(Theme.background.opacity(0.55))
}

extension EnvironmentValues {
    /// False draws plain fills where the popover would use Liquid Glass. Glass needs a live
    /// window behind it, and an offscreen render of it comes out blank, so the snapshot tool
    /// turns it off.
    @Entry public var drawsGlass = true
}

extension View {
    /// The panel's glass, or the same shape filled with the tint when glass is off.
    @ViewBuilder
    fileprivate func popoverGlass(_ glass: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.panelCornerRadius, style: .continuous)
        if glass {
            glassEffect(PopoverGlass.panel, in: shape)
        } else {
            background(shape.fill(Theme.background.opacity(0.92)))
                .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
        }
    }

    /// Glass buttons, or bordered ones when glass is off.
    @ViewBuilder
    fileprivate func popoverButtonStyle(_ glass: Bool, prominent: Bool) -> some View {
        switch (glass, prominent) {
        case (true, true): buttonStyle(.glassProminent)
        case (true, false): buttonStyle(.glass)
        case (false, true): buttonStyle(.borderedProminent)
        case (false, false): buttonStyle(.bordered)
        }
    }
}
