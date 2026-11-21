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

    public init(
        state: ConnectionState, sample: SystemSample?, host: HostInfo?, endpoint: DaemonEndpoint,
        preventSleepOn: Bool, preventSleepError: String?
    ) {
        self.state = state
        self.sample = state.isConnected ? sample : nil
        self.host = host
        self.endpoint = endpoint
        self.preventSleepOn = preventSleepOn
        self.preventSleepError = preventSleepError
    }
}

/// What the popover's controls do.
public struct PopoverActions: Sendable {
    public var setPreventSleep: @MainActor @Sendable (Bool) -> Void
    public var openDashboard: @MainActor @Sendable () -> Void
    public var openPreferences: @MainActor @Sendable () -> Void
    public var quit: @MainActor @Sendable () -> Void

    public init(
        setPreventSleep: @escaping @MainActor @Sendable (Bool) -> Void,
        openDashboard: @escaping @MainActor @Sendable () -> Void,
        openPreferences: @escaping @MainActor @Sendable () -> Void,
        quit: @escaping @MainActor @Sendable () -> Void
    ) {
        self.setPreventSleep = setPreventSleep
        self.openDashboard = openDashboard
        self.openPreferences = openPreferences
        self.quit = quit
    }

    /// Does nothing; for previews and snapshots.
    public static let none = PopoverActions(setPreventSleep: { _ in }, openDashboard: {}, openPreferences: {}, quit: {})
}

/// The popover under the menu bar item: a panel with rings and rows, and a separate capsule
/// with Preferences and Quit below it, as in the reference.
public struct PopoverView: View {
    let content: PopoverContent
    let actions: PopoverActions

    public init(content: PopoverContent, actions: PopoverActions) {
        self.content = content
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: Metrics.gapToCapsule) {
            panel
            bottomCapsule
        }
        .frame(width: Metrics.popoverWidth)
        .environment(\.colorScheme, .dark)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            if case .daemonNotRunning(let problem) = content.state {
                DaemonDownSection(problem: problem)
            } else {
                RingsSection(sample: content.sample)
                SectionDivider()
                StatusRows(content: content)
            }
            SectionDivider()
            ToggleRow(
                label: "Prevent Sleep",
                isOn: content.preventSleepOn,
                message: content.preventSleepError,
                onChange: actions.setPreventSleep
            )
            .padding(.horizontal, Metrics.sidePadding)
            .padding(.vertical, 8)
            SectionDivider()
            Button(action: { actions.openDashboard() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                    Text("Open Dashboard")
                }
                .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(ThemeButtonStyle())
        }
        .background(PanelShape(cornerRadius: Metrics.panelCornerRadius))
    }

    private var bottomCapsule: some View {
        HStack {
            Button("Preferences") { actions.openPreferences() }
            Spacer()
            Button("Quit") { actions.quit() }
        }
        .buttonStyle(ThemeButtonStyle())
        .padding(.horizontal, Metrics.sidePadding)
        .frame(height: Metrics.capsuleHeight)
        .background(PanelShape(cornerRadius: Metrics.capsuleHeight / 2))
    }
}

/// The popover's rounded background with a hairline edge.
struct PanelShape: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.background)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}
