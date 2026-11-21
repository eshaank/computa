import ComputaCore
import SwiftUI

/// The process list's header, like a table's: "App" with, on the Mem tab, a button explaining
/// the three figures, then each column's name with its definition as a tooltip.
struct ProcessColumnsHeader: View {
    let metric: ProcessMetric
    let columns: [ProcessColumn]
    var residentReported = true
    @State private var explaining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                Text("App")
                if metric == .memory { infoButton }
                Spacer(minLength: 8)
                ForEach(columns) { column in
                    Text(column.title)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: column.width, alignment: .trailing)
                        .help(column.help)
                }
            }
            if metric == .memory, !residentReported {
                Label(FigureExplanations.residentNotReported, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, ProcessListMetrics.rowPadding)
        .padding(.vertical, 6)
    }

    private var infoButton: some View {
        Button {
            explaining.toggle()
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .help("What Mem, Compressed + swap and Footprint mean")
        .accessibilityLabel("About the memory figures")
        .popover(isPresented: $explaining, arrowEdge: .bottom) {
            MemoryFiguresExplanation()
        }
    }
}

/// What the Mem list's three figures mean, in a few plain sentences. Shown by the list's info
/// button.
public struct MemoryFiguresExplanation: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Memory figures")
                .font(.headline)
            Text(FigureExplanations.memory)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }
}

/// Why the Net tab's app list has no rates to show.
struct TrafficStatusView: View {
    let availability: TrafficAvailability

    var body: some View {
        switch availability {
        case .available:
            EmptyView()
        case .measuring:
            ContentUnavailableView {
                ProgressView().controlSize(.small)
            } description: {
                Text("Measuring traffic by app…")
            }
        case .problem(let problem):
            ContentUnavailableView {
                Label("No traffic by app", systemImage: "exclamationmark.triangle")
            } description: {
                Text(problem)
            }
        case .daemonNeedsUpdate:
            ContentUnavailableView {
                Label("Daemon needs an update", systemImage: "arrow.down.circle")
            } description: {
                Text("This computad does not measure traffic by app. Update it; Computa picks it up by itself.")
            }
        }
    }
}
