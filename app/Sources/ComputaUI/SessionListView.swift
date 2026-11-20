import ComputaCore
import SwiftUI

/// The session list in its rounded panel. An open session shows its panes, under a caption per
/// tab when it has more than one; an open pane shows its processes. Session rows open a process
/// viewer and pane rows close their pane, through `actions`.
struct SessionListView: View {
    /// Already sorted.
    let sessions: [RexSession]
    let metric: ProcessMetric
    @Binding var expanded: Set<String>
    let actions: SessionActions
    /// Asks before closing; the tab shows the confirmation.
    let requestClose: (PaneCloseRequest) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sessions) { session in
                    SessionRow(
                        session: session, metric: metric, isExpanded: expanded.contains(session.id),
                        isBusy: actions.busy.contains(.session(session.id)),
                        showsControl: actions.isAvailable,
                        onToggle: { toggle(session.id) },
                        onOpenViewer: { actions.perform(.openProcessViewer(sessionID: session.id)) }
                    )
                    if expanded.contains(session.id) {
                        panes(of: session)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.automatic)
        .background(DashboardPanel())
    }

    @ViewBuilder
    private func panes(of session: RexSession) -> some View {
        let grouped = session.tabs.count > 1
        ForEach(session.tabs) { tab in
            if grouped {
                TabCaption(tab: tab, metric: metric)
            }
            ForEach(tab.panes) { pane in
                PaneRow(
                    pane: pane, metric: metric, isExpanded: expanded.contains(pane.id),
                    isBusy: actions.busy.contains(.pane(pane.id)),
                    showsControl: actions.isAvailable,
                    onToggle: { if !pane.processes.isEmpty { toggle(pane.id) } },
                    onClose: { requestClose(PaneCloseRequest(pane: pane, sessionID: session.id, sessionLabel: session.label)) }
                )
                if expanded.contains(pane.id) {
                    ForEach(pane.processes) { process in
                        ProcessRow(
                            process: process, metric: metric, indent: SessionRowMetrics.processIndent,
                            trailing: SessionRowMetrics.valueTrailing
                        )
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

/// Where each level's content starts, so panes sit under their session's icon and processes
/// under their pane's name; and the control slot at the end of session and pane rows.
enum SessionRowMetrics {
    /// Row edge, chevron, gap.
    static let paneIndent: CGFloat = 14 + 10 + 10
    static let paneIconSize: CGFloat = 18
    static let processIndent: CGFloat = paneIndent + 10 + 8 + paneIconSize + 8
    /// The round action control at a row's end.
    static let controlSize: CGFloat = 18
    static let controlGap: CGFloat = 8
    /// Rows without a control end their value here, so every value lines up.
    static let valueTrailing: CGFloat = 14 + controlSize + controlGap
}

/// One session: chevron, glyph, label, pane count, Claude marker, the value and the process
/// viewer button.
struct SessionRow: View {
    let session: RexSession
    let metric: ProcessMetric
    let isExpanded: Bool
    let isBusy: Bool
    /// False on a machine where actions cannot run.
    let showsControl: Bool
    let onToggle: () -> Void
    let onOpenViewer: () -> Void

    var body: some View {
        HStack(spacing: SessionRowMetrics.controlGap) {
            HStack(spacing: 10) {
                Chevron(isExpanded: isExpanded, visible: session.paneCount > 0)
                AppIconView(icon: .symbol("rectangle.split.2x2"))
                Text(session.label.isEmpty ? "Session" : session.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                CountBadge(text: plural(session.paneCount, "pane"))
                if session.claudePaneCount > 0 {
                    ClaudeMarker(count: session.claudePaneCount)
                }
                Spacer(minLength: 8)
                Text(ProcessList.valueText(SessionList.value(session, metric), metric))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            Group {
                if !showsControl {
                    RowControlSpace()
                } else if isBusy {
                    RowBusyIndicator()
                } else {
                    RowIconButton(
                        symbol: "waveform.path.ecg", label: "Open process viewer",
                        hoverTint: Theme.sessions, action: onOpenViewer
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: DashboardMetrics.rowHeight)
        .contextMenu {
            if showsControl {
                Button("Open Process Viewer", action: onOpenViewer)
                    .disabled(isBusy)
            }
        }
    }
}
