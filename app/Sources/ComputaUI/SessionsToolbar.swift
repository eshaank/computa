import ComputaCore
import SwiftUI

/// The row over the drill-in: where you are and the way back on the left, the sort on the right.
///
/// On the overview it reads "Sessions". Deeper, a round back button (also ⌘[) comes first, then
/// a path such as "Sessions › computa › claude" whose earlier parts are links back to them.
struct SessionsToolbar: View {
    let place: SessionPlace
    @Binding var metric: ProcessMetric
    let go: (SessionPlace) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if place != .overview {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .keyboardShortcut("[", modifiers: .command)
                .help("Back (⌘[)")
                .accessibilityLabel("Back")
            }
            path
                .layoutPriority(1)
            Spacer(minLength: 8)
            Picker("Sort by", selection: $metric) {
                Text("Mem").tag(ProcessMetric.memory)
                Text("CPU").tag(ProcessMetric.cpu)
            }
            .pickerStyle(.segmented)
            .tint(Theme.sessions)
            .labelsHidden()
            .fixedSize()
            .help("Sort by memory in RAM or by CPU")
        }
        .frame(minHeight: 30)
    }

    private func back() {
        switch place {
        case .overview: break
        case .session: go(.overview)
        case .pane(_, _, let session): go(.session(session))
        }
    }

    @ViewBuilder
    private var path: some View {
        switch place {
        case .overview:
            title("Sessions")
        case .session(let session):
            HStack(spacing: 4) {
                link("Sessions", fixed: true) { go(.overview) }
                separator
                title(name(session))
            }
        case .pane(let pane, _, let session):
            HStack(spacing: 4) {
                link("Sessions", fixed: true) { go(.overview) }
                separator
                link(name(session)) { go(.session(session)) }
                separator
                title(pane.title)
            }
        }
    }

    private func name(_ session: RexSession) -> String { session.label.isEmpty ? "Session" : session.label }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)
            .help(text)
    }

    private func link(_ text: String, fixed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.title3)
                .foregroundStyle(Theme.dimText)
                .lineLimit(1)
                .truncationMode(.middle)
                .fixedSize(horizontal: fixed, vertical: false)
        }
        .buttonStyle(.plain)
        .help("Back to \(text)")
    }

    private var separator: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.dimText.opacity(0.7))
            .accessibilityHidden(true)
    }
}
