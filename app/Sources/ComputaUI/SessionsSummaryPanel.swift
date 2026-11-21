import ComputaCore
import SwiftUI

/// The top of the Sessions tab, where other tabs have their chart: counts, totals, Claude Code's
/// share, and one bar split by each session's memory. With a session open, its part of the bar
/// stays bright and the rest dims.
struct SessionsSummaryPanel: View {
    let summary: SessionsSummary
    /// Rex's version; empty when unknown.
    let version: String
    /// The open session, if any.
    var highlighted: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(counts)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                if !version.isEmpty {
                    Text("Rex \(version)")
                        .font(.caption)
                        .foregroundStyle(Theme.dimText)
                }
            }
            .lineLimit(1)
            HStack(alignment: .top, spacing: 12) {
                memoryFigure
                figure("CPU", SessionFigures.cpu(summary.cpuPercent), detail: nil)
                claudeFigure
            }
            ShareBar(shares: summary.shares, highlighted: highlighted)
            ShareLegend(shares: summary.shares, highlighted: highlighted)
        }
        .padding(14)
        .sessionSurface()
    }

    private var counts: String {
        [plural(summary.sessionCount, "session"), plural(summary.tabCount, "tab"), plural(summary.paneCount, "pane")]
            .joined(separator: " · ")
    }

    /// "Mem" with the footprint under it; just "Footprint" from an older daemon.
    private var memoryFigure: some View {
        let memory = summary.memory
        return figure(
            MemoryWords.label(memory), SessionFigures.memory(memory),
            detail: memory.isFootprintOnly ? nil : "Footprint \(Format.memory(memory.footprint))"
        )
        .help(MemoryWords.help)
    }

    private var claudeFigure: some View {
        let count = summary.claudePaneCount
        let memory = summary.claudeMemory
        return VStack(alignment: .leading, spacing: 2) {
            Label("Claude Code", systemImage: "sparkle")
                .font(.caption)
                .foregroundStyle(count > 0 ? Theme.sessions : Theme.dimText)
            Text(count > 0 ? plural(count, "pane") : "None")
                .font(.title3.weight(.medium).monospacedDigit())
                .foregroundStyle(count > 0 ? Theme.sessions : Theme.dimText)
            if count > 0 {
                Text("\(MemoryWords.label(memory)) \(SessionFigures.memory(memory))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.sessions.opacity(0.8))
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(MemoryWords.help)
    }

    private func figure(_ label: String, _ value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.dimText)
            Text(value)
                .font(.title3.weight(.medium).monospacedDigit())
                .foregroundStyle(Theme.text)
            if let detail {
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.dimText)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The shade for the session at `index` in the memory order: the full accent first, then
/// fainter steps.
func sessionShade(_ index: Int, of count: Int) -> Color {
    let step = count > 1 ? 0.6 / Double(count - 1) : 0
    return Theme.sessions.opacity(1 - min(0.6, step * Double(index)))
}

/// One horizontal bar, each session's memory share a segment, with the charts' soft glow.
struct ShareBar: View {
    let shares: [SessionsSummary.Share]
    var highlighted: String?

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let minimum: CGFloat = 2
            // Every segment gets the minimum, and the rest is split by share, so a tiny session
            // still shows and the segments add up to the track exactly.
            let usable = max(0, proxy.size.width - gap * CGFloat(max(0, shares.count - 1)) - minimum * CGFloat(shares.count))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track.opacity(0.6))
                HStack(spacing: gap) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        Capsule()
                            .fill(sessionShade(index, of: shares.count))
                            .opacity(highlighted == nil || highlighted == share.id ? 1 : 0.3)
                            .frame(width: minimum + usable * CGFloat(share.fraction))
                    }
                }
                .glow(Theme.sessions)
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Memory by session")
    }
}

/// Session names with their shade and share under the bar.
struct ShareLegend: View {
    let shares: [SessionsSummary.Share]
    var highlighted: String?

    /// As many sessions as fit on one line, largest first, then "+N more".
    var body: some View {
        ViewThatFits(in: .horizontal) {
            legend(limit: 4)
            legend(limit: 3)
            legend(limit: 2)
            legend(limit: 1)
            legend(limit: 0)
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// At its ideal width, so `ViewThatFits` can tell whether it fits.
    private func legend(limit: Int) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(shares.prefix(limit).enumerated()), id: \.element.id) { index, share in
                HStack(spacing: 5) {
                    Circle().fill(sessionShade(index, of: shares.count)).frame(width: 7, height: 7)
                    Text(share.label)
                        .foregroundStyle(highlighted == share.id ? Theme.text : Theme.dimText)
                        .truncationMode(.middle)
                        .frame(maxWidth: 130, alignment: .leading)
                    Text(Format.percent(share.fraction * 100)).foregroundStyle(Theme.text.opacity(0.85))
                }
            }
            if shares.count > limit {
                Text(limit == 0 ? plural(shares.count, "session") : "+\(shares.count - limit) more")
                    .foregroundStyle(Theme.dimText)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}
