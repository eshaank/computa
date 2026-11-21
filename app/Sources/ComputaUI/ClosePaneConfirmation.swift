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
            Text("Close this pane?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            details
            Text(consequence)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(action: onCancel) { SheetButtonLabel(title: "Cancel", fill: Theme.track, text: Theme.text) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                Button(action: onConfirm) { SheetButtonLabel(title: "Close Pane", fill: Theme.warning, text: .white) }
                    .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    private var details: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
            GridRow {
                label("Program")
                HStack(spacing: 6) {
                    Text(request.pane.title)
                        .font(.system(size: 12.5, weight: .semibold))
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
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
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
            .font(.system(size: 11))
            .foregroundStyle(Theme.dimText)
            .gridColumnAlignment(.trailing)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.text.opacity(0.9))
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// A filled, rounded button face for the sheet.
private struct SheetButtonLabel: View {
    let title: String
    let fill: Color
    let text: Color

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
            .contentShape(Rectangle())
    }
}
