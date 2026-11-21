import ComputaCore
import SwiftUI

/// One pane in a session: its tile, program and Claude Code tag, its folder under the name, Mem
/// and CPU, the close button, and a chevron saying a click opens it. While it closes, the row
/// dims and says so.
struct PaneRow: View {
    let pane: RexPane
    let metric: ProcessMetric
    let showsClose: Bool
    let isBusy: Bool
    let open: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) { content }
                .buttonStyle(.plain)
                .help("Show the processes in this pane")
            if showsClose {
                ClosePaneButton(isBusy: isBusy, action: close)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.dimText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(hovering ? 0.04 : 0))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Show Processes", action: open)
            if showsClose {
                Button("Close Pane…", role: .destructive, action: close).disabled(isBusy)
            }
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            PaneTile(kind: pane.kind)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pane.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if pane.isClaude { ClaudeTag() }
                }
                if !pane.workingDirectory.isEmpty {
                    Text(WorkingDirectory.abbreviatingHome(pane.workingDirectory))
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(pane.workingDirectory)
                }
            }
            Spacer(minLength: 8)
            values
        }
        .opacity(isBusy ? 0.55 : 1)
        .contentShape(Rectangle())
    }

    /// The sorted-by figure first and brighter, the other under it.
    private var values: some View {
        let memory = "\(MemoryWords.label(pane.memory)) \(SessionFigures.memory(pane.memory))"
        let cpu = "CPU \(SessionFigures.cpu(pane.cpuPercent))"
        let (first, second) = metric == .memory ? (memory, cpu) : (cpu, memory)
        return VStack(alignment: .trailing, spacing: 2) {
            Text(isBusy ? "Closing…" : first)
                .font(.callout.monospacedDigit())
                .foregroundStyle(isBusy ? Theme.dimText : Theme.text)
            Text(second)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.dimText)
        }
        .lineLimit(1)
        .fixedSize()
        .help(MemoryWords.help)
    }
}
