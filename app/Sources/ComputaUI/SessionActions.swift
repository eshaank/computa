import ComputaCore
import SwiftUI

/// What the Sessions tab's action controls show and do, as plain values and a closure, so
/// snapshots can set them.
public struct SessionActions: Sendable {
    /// Sessions and panes with an action running, or panes just closed.
    public var busy: Set<RexActionTarget>
    /// The last outcome, shown beside the sort control until it clears.
    public var outcome: RexActionOutcome?
    /// Set when actions cannot run on the shown machine (a remote one without a Rex host
    /// label): the controls are hidden and this dim line says why.
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
}

/// A small round icon button at the end of a row: quiet until the pointer is over it.
struct RowIconButton: View {
    let symbol: String
    let label: String
    var hoverTint: Color = Theme.text
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? hoverTint : Theme.dimText)
                .frame(width: SessionRowMetrics.controlSize, height: SessionRowMetrics.controlSize)
                .background(Circle().fill(Theme.track.opacity(hovering ? 0.9 : 0.4)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Keeps a row control's space where actions cannot run, so values stay in their column.
struct RowControlSpace: View {
    var body: some View {
        Color.clear.frame(width: SessionRowMetrics.controlSize, height: SessionRowMetrics.controlSize)
    }
}

/// Takes a row control's place while its action runs.
struct RowBusyIndicator: View {
    var body: some View {
        ProgressView()
            .controlSize(.mini)
            .frame(width: SessionRowMetrics.controlSize, height: SessionRowMetrics.controlSize)
            .accessibilityLabel("Working")
    }
}

/// The last action's outcome: a tick in the accent colour, or a warning with what to do.
struct ActionOutcomeLine: View {
    let outcome: RexActionOutcome

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
            // Non-breaking hyphens keep "install-rex-actions" on one line.
            Text(outcome.text.replacingOccurrences(of: "-", with: "\u{2011}"))
                .font(.system(size: 11, weight: outcome.succeeded ? .medium : .regular))
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(outcome.succeeded ? Theme.accent : Theme.warning)
        .help(outcome.text)
        .accessibilityElement(children: .combine)
    }
}
