import ComputaCore
import SwiftUI

/// The Sessions tab's screens for when there are no sessions to show: loading, none open, Rex
/// not reachable, and the daemon down or too old.
enum SessionStateScreen {
    case loading
    case noSessions
    case rexUnreachable(problem: String)
    case daemon(DaemonProblem)
}

struct SessionStateView: View {
    let screen: SessionStateScreen

    var body: some View {
        Group {
            switch screen {
            case .loading:
                ContentUnavailableView {
                    ProgressView().controlSize(.regular)
                    Text("Loading Sessions…").font(.title3)
                }
            case .noSessions:
                unavailable(
                    "No Rex Sessions", symbol: "rectangle.stack", tint: Theme.dimText,
                    lines: ["Sessions you open in Rex show here, with what their panes use."]
                )
            case .rexUnreachable(let problem):
                unavailable(
                    "Rex Not Reachable", symbol: "terminal", tint: Theme.warning,
                    lines: [
                        problem.isEmpty ? "computad could not reach Rex." : problem,
                        "The other tabs still work. This one fills in as soon as Rex answers.",
                    ]
                )
            case .daemon(let problem):
                unavailable(
                    daemonTitle(problem), symbol: "bolt.horizontal.circle", tint: Theme.warning,
                    lines: [
                        problem.summary,
                        problem.kind == .unsupported
                            ? "Update computad; Computa picks it up by itself."
                            : "Computa will reconnect by itself as soon as it answers.",
                    ]
                )
            }
        }
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sessionSurface()
    }

    private func unavailable(_ title: String, symbol: String, tint: Color, lines: [String]) -> some View {
        ContentUnavailableView {
            Label {
                Text(title).foregroundStyle(Theme.text)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint).glow(tint)
            }
        } description: {
            VStack(spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line).foregroundStyle(index == 0 ? Theme.text.opacity(0.85) : Theme.dimText)
                }
            }
        }
    }

    private func daemonTitle(_ problem: DaemonProblem) -> String {
        switch problem.kind {
        case .unreachable: "Daemon Not Running"
        case .unsupported: "Daemon Needs an Update"
        case .streamEnded, .other: "Daemon Not Responding"
        }
    }
}
