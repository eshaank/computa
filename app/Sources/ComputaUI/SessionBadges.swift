import ComputaCore
import SwiftUI

/// The disclosure chevron, turned down when open. Invisible (but still taking its room) when
/// there is nothing to open.
struct Chevron: View {
    let isExpanded: Bool
    var visible = true
    var size: CGFloat = 11

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Theme.text.opacity(0.75))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .frame(width: 10)
            .opacity(visible ? 1 : 0)
    }
}

/// A pane's glyph: Claude Code in the accent colour with a glow, a terminal for a shell, a
/// generic program glyph otherwise.
struct PaneIcon: View {
    let kind: PaneKind
    var size: CGFloat = SessionRowMetrics.paneIconSize

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(kind == .claude ? Theme.sessions.opacity(0.18) : Theme.track)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(kind == .claude ? Theme.sessions : Theme.text.opacity(0.8))
                    .shadow(color: kind == .claude ? Theme.sessions.opacity(0.7) : .clear, radius: 3)
            )
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch kind {
        case .claude: "sparkle"
        case .shell: "terminal"
        case .program, .unspecified: "app.dashed"
        }
    }
}

/// The small "Claude" tag beside a Claude Code pane's name.
struct ClaudeTag: View {
    var body: some View {
        Text("Claude")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Theme.sessions)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.sessions.opacity(0.15)))
            .fixedSize()
    }
}

/// On a session row: how many of its panes run Claude Code, so they show without opening it.
struct ClaudeMarker: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .bold))
            Text(verbatim: "\(count)")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(Theme.sessions)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.sessions.opacity(0.14)))
        .fixedSize()
        .accessibilityLabel("\(count) running Claude Code")
    }
}
