import ComputaCore
import SwiftUI

/// The top of the Sessions tab, where other tabs have their chart: counts, totals, Claude Code's
/// share, and one bar split by each session's memory.
struct SessionsSummaryPanel: View {
    let summary: SessionsSummary
    /// Rex's version; empty when unknown.
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(counts)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                if !version.isEmpty {
                    Text("Rex \(version)")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(Theme.dimText)
                }
            }
            .lineLimit(1)
            HStack(alignment: .top, spacing: 0) {
                figure("Memory", Format.memory(summary.memoryBytes), color: Theme.text)
                figure("CPU", Format.cpuShare(summary.cpuPercent), color: Theme.text)
                figure("Claude Code", claudeText, color: summary.claudePaneCount > 0 ? Theme.sessions : Theme.dimText, symbol: "sparkle")
            }
            ShareBar(shares: summary.shares)
            ShareLegend(shares: summary.shares)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(DashboardPanel())
    }

    private var counts: String {
        [
            plural(summary.sessionCount, "session"), plural(summary.tabCount, "tab"), plural(summary.paneCount, "pane"),
        ].joined(separator: " · ")
    }

    private var claudeText: String {
        guard summary.claudePaneCount > 0 else { return "none" }
        return "\(plural(summary.claudePaneCount, "pane")) · \(Format.memory(summary.claudeMemoryBytes))"
    }

    private func figure(_ label: String, _ value: String, color: Color, symbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
                Text(label.uppercased())
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(symbol == nil ? Theme.dimText : color.opacity(0.85))
            Text(value)
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func plural(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
}

/// The shade for the session at `index` in the memory order: the full accent first, then
/// darker steps toward the panel colour.
func sessionShade(_ index: Int, of count: Int) -> Color {
    let step = count > 1 ? 0.62 / Double(count - 1) : 0
    return Color(hex: blend(DashboardTab.sessions.hex, 0x20222E, min(0.62, step * Double(index))))
}

/// One horizontal bar, each session's memory share a segment, with the charts' soft glow.
struct ShareBar: View {
    let shares: [SessionsSummary.Share]

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let minimum: CGFloat = 2
            // Every segment gets the minimum, and the rest is split by share, so a tiny session
            // still shows and the segments add up to the track exactly.
            let usable = max(0, proxy.size.width - gap * CGFloat(max(0, shares.count - 1)) - minimum * CGFloat(shares.count))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.track)
                HStack(spacing: gap) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(sessionShade(index, of: shares.count))
                            .frame(width: minimum + usable * CGFloat(share.fraction))
                    }
                }
                .shadow(color: Theme.sessions.opacity(0.5), radius: 6)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Memory by session")
    }
}

/// Session names with their shade and share under the bar.
struct ShareLegend: View {
    let shares: [SessionsSummary.Share]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(shares.prefix(4).enumerated()), id: \.element.id) { index, share in
                HStack(spacing: 5) {
                    Circle().fill(sessionShade(index, of: shares.count)).frame(width: 7, height: 7)
                    Text(share.label).foregroundStyle(Theme.dimText).lineLimit(1)
                    Text(Format.percent(share.fraction * 100)).foregroundStyle(Theme.text.opacity(0.85))
                }
            }
            if shares.count > 4 {
                Text("+\(shares.count - 4)").foregroundStyle(Theme.dimText)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11).monospacedDigit())
    }
}
