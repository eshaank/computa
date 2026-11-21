import ComputaCore
import SwiftUI

/// A pane the user asked to close, with the session it is in.
public struct PaneCloseRequest: Identifiable, Equatable, Sendable {
    public var pane: RexPane
    public var sessionID: String
    public var sessionLabel: String

    public init(pane: RexPane, sessionID: String, sessionLabel: String) {
        self.pane = pane
        self.sessionID = sessionID
        self.sessionLabel = sessionLabel
    }

    public var id: String { pane.id }
    public var action: RexAction { .closePane(sessionID: sessionID, paneID: pane.id) }
}

/// The sheet that asks before a pane closes: what will close, and that its program will end.
public struct ClosePaneConfirmation: View {
    let request: PaneCloseRequest
    let onCancel: () -> Void
    let onConfirm: () -> Void

    public init(request: PaneCloseRequest, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.request = request
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("Close this pane?").font(.headline).foregroundStyle(Theme.text)
            } icon: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.warning)
            }
            details
            Text(consequence)
                .font(.callout)
                .foregroundStyle(Theme.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Close Pane", role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.warning)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 360)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    private var details: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
            GridRow {
                label("Program")
                HStack(spacing: 6) {
                    Text(request.pane.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.text)
                    if request.pane.isClaude { ClaudeTag() }
                }
            }
            GridRow {
                label("Folder")
                value(request.pane.workingDirectory.isEmpty ? "Unknown" : WorkingDirectory.display(request.pane.workingDirectory, maxLength: 40))
            }
            GridRow {
                label("Session")
                value(request.sessionLabel.isEmpty ? "Session" : request.sessionLabel)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sessionSurface(radius: SessionMetrics.groupRadius)
    }

    /// "claude and 3 other processes in this pane will end."
    private var consequence: String {
        let others = max(request.pane.processCount - 1, 0)
        let rest = switch others {
        case 0: ""
        case 1: " and 1 other process"
        default: " and \(others) other processes"
        }
        return "\(request.pane.title)\(rest) in this pane will end. Unsaved work there is lost."
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.dimText)
            .gridColumnAlignment(.trailing)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.text.opacity(0.9))
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
