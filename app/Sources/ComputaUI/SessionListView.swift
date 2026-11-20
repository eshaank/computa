import ComputaCore
import SwiftUI

/// The session list in its rounded panel. An open session shows its panes, under a caption per
/// tab when it has more than one; an open pane shows its processes.
struct SessionListView: View {
    /// Already sorted.
    let sessions: [RexSession]
    let metric: ProcessMetric
    @Binding var expanded: Set<String>

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sessions) { session in
                    SessionRow(session: session, metric: metric, isExpanded: expanded.contains(session.id)) {
                        toggle(session.id)
                    }
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
                PaneRow(pane: pane, metric: metric, isExpanded: expanded.contains(pane.id)) {
                    if !pane.processes.isEmpty { toggle(pane.id) }
                }
                if expanded.contains(pane.id) {
                    ForEach(pane.processes) { process in
                        ProcessRow(process: process, metric: metric, indent: SessionRowMetrics.processIndent)
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
/// under their pane's name.
enum SessionRowMetrics {
    /// Row edge, chevron, gap.
    static let paneIndent: CGFloat = 14 + 10 + 10
    static let paneIconSize: CGFloat = 18
    static let processIndent: CGFloat = paneIndent + 10 + 8 + paneIconSize + 8
}

/// One session: chevron, glyph, label, pane count, Claude marker and the value.
struct SessionRow: View {
    let session: RexSession
    let metric: ProcessMetric
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
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
        .padding(.horizontal, 14)
        .frame(height: DashboardMetrics.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

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
        .padding(.trailing, 14)
        .padding(.top, 6)
        .frame(height: 22, alignment: .bottom)
    }
}

/// One pane: chevron, kind glyph, program, Claude tag, process count, its directory under the
/// name, and the value.
struct PaneRow: View {
    let pane: RexPane
    let metric: ProcessMetric
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Chevron(isExpanded: isExpanded, visible: !pane.processes.isEmpty, size: 9.5)
            PaneIcon(kind: pane.kind)
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
            Spacer(minLength: 8)
            Text(ProcessList.valueText(SessionList.value(pane, metric), metric))
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundStyle(Theme.text.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.leading, SessionRowMetrics.paneIndent)
        .padding(.trailing, 14)
        .frame(minHeight: 38)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(pane.processes.isEmpty ? [] : .isButton)
    }
}
