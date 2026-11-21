import ComputaCore
import SwiftUI

/// What the Sessions tab's action controls show and do, as plain values and a closure, so
/// snapshots can set them.
public struct SessionActions: Sendable {
    /// Sessions and panes with an action running, or panes just closed.
    public var busy: Set<RexActionTarget>
    /// The last outcome, shown at the foot of the tab until it clears.
    public var outcome: RexActionOutcome?
    /// Set when actions cannot run on the shown machine (a remote one without a Rex host
    /// label): the controls are hidden and this line says why.
    public var unavailableNote: String?
    public var perform: @MainActor @Sendable (RexAction) -> Void

    public init(
        busy: Set<RexActionTarget>, outcome: RexActionOutcome?, unavailableNote: String? = nil,
        perform: @escaping @MainActor @Sendable (RexAction) -> Void
    ) {
        self.busy = busy
        self.outcome = outcome
        self.unavailableNote = unavailableNote
        self.perform = perform
    }

    /// No controls, and a line saying why.
    public static func unavailable(_ note: String) -> SessionActions {
        SessionActions(busy: [], outcome: nil, unavailableNote: note, perform: { _ in })
    }

    public var isAvailable: Bool { unavailableNote == nil }

    /// Does nothing; for previews and snapshots.
    public static let none = SessionActions(busy: [], outcome: nil, perform: { _ in })

    func isBusy(_ session: RexSession) -> Bool { busy.contains(.session(session.id)) }
    func isBusy(_ pane: RexPane) -> Bool { busy.contains(.pane(pane.id)) }
}

/// Opens a session's process viewer. On a card it is a round glass button with the glyph; in a
/// session's header it has its title too. While the action runs, a spinner takes its place.
struct ProcessViewerButton: View {
    var titled = false
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        if isBusy {
            busy
        } else {
            Button(action: action) {
                if titled {
                    Label("Process Viewer", systemImage: "waveform.path.ecg")
                        .foregroundStyle(Theme.text)
                } else {
                    Image(systemName: "waveform.path.ecg")
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Theme.text)
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(titled ? .capsule : .circle)
            .controlSize(titled ? .regular : .small)
            .help("Open a process viewer in this session")
            .accessibilityLabel("Open process viewer")
        }
    }

    private var busy: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            if titled { Text("Opening…").font(.callout).foregroundStyle(Theme.dimText) }
        }
        .frame(minWidth: 24, minHeight: 24)
        .accessibilityLabel("Opening process viewer")
    }
}

/// Asks to close a pane. In a row it is a round glyph button; in a pane's header it has its title.
struct ClosePaneButton: View {
    var titled = false
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        if isBusy {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                if titled { Text("Closing…").font(.callout).foregroundStyle(Theme.dimText) }
            }
            .frame(minWidth: 24, minHeight: 24)
            .accessibilityLabel("Closing pane")
        } else if titled {
            Button(role: .destructive, action: action) {
                Label("Close Pane…", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Theme.warning)
            .help("Close this pane and end its programs")
        } else {
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .help("Close pane…")
            .accessibilityLabel("Close pane")
        }
    }
}

/// The last action's outcome: a tick, or a warning with what to do.
struct ActionOutcomeLine: View {
    let outcome: RexActionOutcome

    var body: some View {
        Label {
            // Non-breaking hyphens keep "install-rex-actions" on one line.
            Text(outcome.text.replacingOccurrences(of: "-", with: "\u{2011}"))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .foregroundStyle(outcome.succeeded ? Theme.cpu : Theme.warning)
        .help(outcome.text)
    }
}

/// Why actions cannot run on this machine.
struct ActionsUnavailableLine: View {
    let note: String

    var body: some View {
        Label(note, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(Theme.dimText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
