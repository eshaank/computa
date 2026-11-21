import ComputaCore
import SwiftUI

/// Sizes shared by the Sessions tab's views.
enum SessionMetrics {
    static let cardRadius: CGFloat = 14
    static let groupRadius: CGFloat = 12
    static let gap: CGFloat = 10
    /// The narrowest a session card gets before the grid drops a column.
    static let cardMinimumWidth: CGFloat = 190
}

/// What "Mem" and "Footprint" mean, on every figure that shows either.
enum MemoryWords {
    static let help = "Mem is what is in RAM now. Footprint also counts memory macOS has compressed "
        + "or moved to swap, so it can exceed the RAM installed."

    /// "Mem", or "Footprint" when an older daemon left the resident size unknown.
    static func label(_ memory: SessionMemory) -> String { memory.isFootprintOnly ? "Footprint" : "Mem" }
}

/// The surface under cards and grouped rows: a light frosted layer over the window, with a hairline
/// edge, like the grouped sections of System Settings.
struct SessionSurface: ViewModifier {
    var radius: CGFloat = SessionMetrics.cardRadius
    var highlighted = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(Color.white.opacity(highlighted ? 0.085 : 0.05)))
            .overlay(shape.strokeBorder(Color.white.opacity(highlighted ? 0.14 : 0.07), lineWidth: 1))
    }
}

extension View {
    func sessionSurface(radius: CGFloat = SessionMetrics.cardRadius, highlighted: Bool = false) -> some View {
        modifier(SessionSurface(radius: radius, highlighted: highlighted))
    }
}

/// A coloured, rounded icon tile, as in System Settings' sidebar.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// The tile for a pane: Claude Code in the sessions pink with its glow, a shell in green, any
/// other program in blue-grey.
struct PaneTile: View {
    let kind: PaneKind
    var size: CGFloat = 28

    var body: some View {
        IconTile(symbol: symbol, tint: tint, size: size)
            .glow(Theme.sessions, isOn: kind == .claude)
    }

    private var symbol: String {
        switch kind {
        case .claude: "sparkle"
        case .shell: "apple.terminal"
        case .program, .unspecified: "app.dashed"
        }
    }

    private var tint: Color {
        switch kind {
        case .claude: Theme.sessions
        case .shell: Color(hex: 0x2F8F5B)
        case .program, .unspecified: Theme.track
        }
    }
}

/// The tile for a session: pink when Claude Code runs in it.
struct SessionTile: View {
    let session: RexSession
    var size: CGFloat = 28

    var body: some View {
        IconTile(
            symbol: "rectangle.split.2x2", tint: session.claudePaneCount > 0 ? Theme.sessions : Theme.track, size: size
        )
    }
}

/// The small "Claude Code" tag beside a pane's name.
struct ClaudeTag: View {
    var body: some View {
        Text("Claude Code")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.sessions)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.sessions.opacity(0.16)))
            .fixedSize()
    }
}

/// How many of a session's panes run Claude Code.
struct ClaudeCount: View {
    let count: Int

    var body: some View {
        Label("\(count)", systemImage: "sparkle")
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(Theme.sessions)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.sessions.opacity(0.16)))
            .fixedSize()
            .help(count == 1 ? "1 pane running Claude Code" : "\(count) panes running Claude Code")
            .accessibilityLabel("\(count) running Claude Code")
    }
}

/// A small caption over a figure: "Mem" / "1.2 GB".
struct Figure: View {
    let label: String
    let value: String
    var emphasized = true
    var tint: Color = Theme.text
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.dimText)
            Text(value)
                .font(.body.weight(emphasized ? .medium : .regular).monospacedDigit())
                .foregroundStyle(emphasized ? tint : tint.opacity(0.75))
                .lineLimit(1)
        }
        .help(help ?? "")
        .accessibilityElement(children: .combine)
    }
}

/// The figure texts for a session, tab or pane.
enum SessionFigures {
    static func memory(_ memory: SessionMemory) -> String { Format.memory(memory.shownBytes) }
    static func cpu(_ percent: Double) -> String { Format.cpuShare(percent.isFinite ? max(0, percent) : 0) }
}

func plural(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
}
