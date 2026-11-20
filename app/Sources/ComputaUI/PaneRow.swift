import ComputaCore
import SwiftUI

/// The dim caption over a tab's panes, with the tab's total.
struct TabCaption: View {
    let tab: RexTab
    let metric: ProcessMetric

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "macwindow")
                .font(.system(size: 9.5, weight: .semibold))
            Text(tab.label.isEmpty ? "Tab" : tab.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(ProcessList.valueText(SessionList.value(tab, metric), metric))
        }
        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
        .foregroundStyle(Theme.dimText)
        .padding(.leading, SessionRowMetrics.paneIndent)
        .padding(.trailing, SessionRowMetrics.valueTrailing)
        .padding(.top, 6)
        .frame(height: 22, alignment: .bottom)
    }
}

/// One pane: chevron, kind glyph, program, Claude tag, process count, its directory under the
/// name, the value and the close control. While it closes, the row dims and says so.
struct PaneRow: View {
    let pane: RexPane
    let metric: ProcessMetric
    let isExpanded: Bool
    let isBusy: Bool
    let onToggle: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: SessionRowMetrics.controlGap) {
            HStack(spacing: 8) {
                Chevron(isExpanded: isExpanded, visible: !pane.processes.isEmpty, size: 9.5)
                PaneIcon(kind: pane.kind)
                name
                Spacer(minLength: 8)
                Text(isBusy ? "Closing…" : ProcessList.valueText(SessionList.value(pane, metric), metric))
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(isBusy ? Theme.dimText : Theme.text.opacity(0.85))
                    .lineLimit(1)
            }
            .opacity(isBusy ? 0.6 : 1)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(pane.processes.isEmpty ? [] : .isButton)
            control
        }
        .padding(.leading, SessionRowMetrics.paneIndent)
        .padding(.trailing, 14)
        .frame(minHeight: 38)
        .contextMenu {
            Button("Close Pane…", action: onClose)
                .disabled(isBusy)
        }
    }

    @ViewBuilder
    private var control: some View {
        if isBusy {
            RowBusyIndicator()
        } else {
            RowIconButton(symbol: "xmark", label: "Close pane…", hoverTint: Theme.warning, action: onClose)
        }
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(pane.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text.opacity(0.92))
                    .lineLimit(1)
                if pane.isClaude { ClaudeTag() }
                if let badge = pane.badge { CountBadge(text: badge) }
            }
            if !pane.workingDirectory.isEmpty {
                Text(WorkingDirectory.display(pane.workingDirectory))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.dimText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
