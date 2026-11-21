import ComputaCore
import SwiftUI

/// Every session as a card, in as many columns as the window fits. A click on a card opens the
/// session.
struct SessionCardGrid: View {
    /// Already sorted.
    let sessions: [RexSession]
    let summary: SessionsSummary
    let metric: ProcessMetric
    let actions: SessionActions
    let open: (RexSession) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: SessionMetrics.cardMinimumWidth), spacing: SessionMetrics.gap)],
                spacing: SessionMetrics.gap
            ) {
                ForEach(sessions) { session in
                    SessionCard(
                        session: session, share: share(of: session), metric: metric,
                        showsViewer: actions.isAvailable, viewerBusy: actions.isBusy(session),
                        open: { open(session) },
                        openViewer: { actions.perform(.openProcessViewer(sessionID: session.id)) }
                    )
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.automatic)
    }

    private func share(of session: RexSession) -> Double? {
        summary.shares.first { $0.id == session.id }?.fraction
    }
}

/// One session: its tile and name, how many panes and how many run Claude Code, Mem and CPU,
/// and its part of all sessions' memory. The whole card is the button that opens it; the round
/// button in its corner opens a process viewer instead.
struct SessionCard: View {
    let session: RexSession
    /// Of the summary's memory, 0...1; nil when no session uses memory.
    let share: Double?
    let metric: ProcessMetric
    let showsViewer: Bool
    let viewerBusy: Bool
    let open: () -> Void
    let openViewer: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) { content }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                if showsViewer {
                    ProcessViewerButton(isBusy: viewerBusy, action: openViewer)
                        .padding(10)
                }
            }
            .sessionSurface(highlighted: hovering)
            .onHover { hovering = $0 }
            .help("Show the panes in \(name)")
            .contextMenu {
                Button("Show Panes", action: open)
                if showsViewer {
                    Button("Open Process Viewer", action: openViewer).disabled(viewerBusy)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(name)
    }

    private var name: String { session.label.isEmpty ? "Session" : session.label }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            SessionTile(session: session)
            Text(name)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 6) {
                Text(counts)
                    .font(.subheadline)
                    .foregroundStyle(Theme.dimText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if session.claudePaneCount > 0 { ClaudeCount(count: session.claudePaneCount) }
            }
            .frame(height: 20)
            figures
            ShareMeter(fraction: share ?? 0, tint: session.claudePaneCount > 0 ? Theme.sessions : Theme.text.opacity(0.55))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: SessionMetrics.cardRadius, style: .continuous))
    }

    private var counts: String {
        let panes = plural(session.paneCount, "pane")
        return session.tabs.count > 1 ? "\(panes) · \(plural(session.tabs.count, "tab"))" : panes
    }

    private var figures: some View {
        let memory = session.memory
        return HStack(alignment: .top, spacing: 12) {
            SessionFigure(
                label: SessionMemoryWords.label(memory), value: SessionFigures.memory(memory), emphasized: metric == .memory,
                help: "\(SessionMemoryWords.help) Footprint here: \(Format.memory(memory.footprint))."
            )
            SessionFigure(label: "CPU", value: SessionFigures.cpu(session.cpuPercent), emphasized: metric == .cpu)
            Spacer(minLength: 0)
        }
    }
}

/// A thin bar for one session's part of all sessions' memory, with the percentage.
struct ShareMeter: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track.opacity(0.6))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, proxy.size.width * CGFloat(min(max(fraction, 0), 1))))
                }
            }
            .frame(height: 5)
            Text(Format.percent(fraction * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.dimText)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .help("Share of all sessions' memory")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Format.percent(fraction * 100)) of all sessions' memory")
    }
}
