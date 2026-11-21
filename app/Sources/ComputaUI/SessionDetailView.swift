import ComputaCore
import SwiftUI

/// One session opened: a header with its figures and the process viewer button, then its panes in
/// grouped boxes, one per tab when it has more than one. A click on a pane opens it.
struct SessionDetailView: View {
    /// Already sorted.
    let session: RexSession
    let metric: ProcessMetric
    let actions: SessionActions
    let openPane: (RexPane) -> Void
    let requestClose: (PaneCloseRequest) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SessionHeader(session: session, actions: actions)
                ForEach(SessionNavigation.groups(session)) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        if let tab = group.tab { TabHeading(tab: tab) }
                        rows(group.panes)
                    }
                }
                if session.panes.isEmpty {
                    Text("This session has no panes.")
                        .font(.callout)
                        .foregroundStyle(Theme.dimText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.automatic)
    }

    private func rows(_ panes: [RexPane]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                if index > 0 { Divider().padding(.leading, 52) }
                PaneRow(
                    pane: pane, metric: metric, showsClose: actions.isAvailable, isBusy: actions.isBusy(pane),
                    open: { openPane(pane) },
                    close: { requestClose(PaneCloseRequest(pane: pane, sessionID: session.id, sessionLabel: session.label)) }
                )
            }
        }
        .sessionSurface(radius: SessionMetrics.groupRadius)
    }
}

/// The session's tile, name and counts, its figures, and the process viewer button.
struct SessionHeader: View {
    let session: RexSession
    let actions: SessionActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                SessionTile(session: session, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.label.isEmpty ? "Session" : session.label)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(counts)
                        .font(.subheadline)
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if actions.isAvailable {
                    ProcessViewerButton(
                        titled: true, isBusy: actions.isBusy(session),
                        action: { actions.perform(.openProcessViewer(sessionID: session.id)) }
                    )
                    .fixedSize()
                }
            }
            figures
        }
        .padding(14)
        .sessionSurface()
    }

    private var counts: String {
        let processes = session.processCount == 1 ? "1 process" : "\(session.processCount) processes"
        return [plural(session.paneCount, "pane"), plural(session.tabs.count, "tab"), processes].joined(separator: " · ")
    }

    private var figures: some View {
        let memory = session.memory
        return HStack(alignment: .top, spacing: 12) {
            Figure(label: MemoryWords.label(memory), value: SessionFigures.memory(memory), help: MemoryWords.help)
            if !memory.isFootprintOnly {
                Figure(label: "Footprint", value: Format.memory(memory.footprint), emphasized: false, help: MemoryWords.help)
            }
            Figure(label: "CPU", value: SessionFigures.cpu(session.cpuPercent))
            if session.claudePaneCount > 0 {
                Figure(label: "Claude Code", value: plural(session.claudePaneCount, "pane"), tint: Theme.sessions)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The heading over a tab's panes: its name, and its panes' Mem and CPU.
struct TabHeading: View {
    let tab: RexTab

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(tab.label.isEmpty ? "Tab" : tab.label, systemImage: "macwindow")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text("\(MemoryWords.label(tab.memory)) \(SessionFigures.memory(tab.memory)) · CPU \(SessionFigures.cpu(tab.cpuPercent))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.dimText)
                .lineLimit(1)
                .help(MemoryWords.help)
        }
        .padding(.horizontal, 4)
    }
}
