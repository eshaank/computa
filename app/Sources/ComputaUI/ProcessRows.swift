import ComputaCore
import SwiftUI

/// One figure column of the process list: its header, tooltip and width. Header and rows use
/// the same widths, so the figures line up under their headings.
struct ProcessColumn: Identifiable {
    let title: String
    let help: String
    let width: CGFloat
    /// The main figure is drawn in the primary colour, the others dimmer.
    var isMain = false

    var id: String { title }

    /// The columns for a metric, left to right.
    static func columns(_ metric: ProcessMetric) -> [ProcessColumn] {
        switch metric {
        case .cpu:
            [ProcessColumn(title: "% CPU", help: "Share of one core: 100% is one core fully busy.", width: 64, isMain: true)]
        case .memory:
            [
                ProcessColumn(title: "Mem", help: FigureExplanations.memHelp, width: 64, isMain: true),
                ProcessColumn(title: "≈ Compressed + swap", help: FigureExplanations.compressedHelp, width: 80),
                ProcessColumn(title: "Footprint", help: FigureExplanations.footprintHelp, width: 68),
            ]
        case .network:
            [
                ProcessColumn(title: "Down", help: FigureExplanations.downHelp, width: 76, isMain: true),
                ProcessColumn(title: "Up", help: FigureExplanations.upHelp, width: 76, isMain: true),
            ]
        }
    }

    /// A group's figures, one per column.
    static func figures(_ group: ProcessGroup, _ metric: ProcessMetric, residentReported: Bool) -> [String] {
        switch metric {
        case .cpu: [ProcessList.valueText(ProcessList.value(group, .cpu), .cpu)]
        case .memory: memory(MemoryFigures(group, residentReported: residentReported))
        case .network: traffic(TrafficFigures(group))
        }
    }

    /// A process's figures, one per column.
    static func figures(_ process: ProcessEntry, _ metric: ProcessMetric, residentReported: Bool) -> [String] {
        switch metric {
        case .cpu: [ProcessList.valueText(ProcessList.value(process, .cpu), .cpu)]
        case .memory: memory(MemoryFigures(process, residentReported: residentReported))
        case .network: traffic(TrafficFigures(process))
        }
    }

    private static func memory(_ figures: MemoryFigures) -> [String] {
        [figures.mem, figures.compressedOrSwapped, figures.footprint]
    }

    private static func traffic(_ figures: TrafficFigures) -> [String] {
        ["↓ \(figures.down)", "↑ \(figures.up)"]
    }
}

/// Figures laid out in their columns.
struct FigureColumns: View {
    let figures: [String]
    let columns: [ProcessColumn]

    var body: some View {
        ForEach(Array(zip(columns, figures)), id: \.0.id) { column, figure in
            Text(figure)
                .foregroundStyle(column.isMain ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: column.width, alignment: .trailing)
        }
    }
}

/// One app's row.
struct GroupRow: View {
    let group: ProcessGroup
    let figures: [String]
    let columns: [ProcessColumn]
    let isExpanded: Bool
    let icon: AppIcon
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 10)
                .opacity(group.processes.count > 1 ? 1 : 0)
            AppIconView(icon: icon)
            Text(group.name)
                .lineLimit(1)
                .truncationMode(.tail)
            if let badge = group.badge {
                CountBadge(text: badge)
            }
            Spacer(minLength: 8)
            FigureColumns(figures: figures, columns: columns)
                .font(.body.monospacedDigit())
        }
        .font(.body)
        .padding(.horizontal, ProcessListMetrics.rowPadding)
        .frame(height: DashboardMetrics.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(group.processes.count > 1 ? .isButton : [])
    }
}

/// One process inside an expanded group: name, pid and figures, indented under the app's name.
struct ProcessRow: View {
    let process: ProcessEntry
    let figures: [String]
    /// Empty when the row has one figure with no column (the Sessions tab).
    var columns: [ProcessColumn] = []
    /// Where the name starts: under the app's name by default.
    var indent: CGFloat = ProcessListMetrics.nameIndent
    /// Where the value ends.
    var trailing: CGFloat = ProcessListMetrics.rowPadding

    /// One figure, as the Sessions tab shows it.
    init(process: ProcessEntry, value: String, indent: CGFloat = ProcessListMetrics.nameIndent, trailing: CGFloat = ProcessListMetrics.rowPadding) {
        self.process = process
        self.figures = [value]
        self.indent = indent
        self.trailing = trailing
    }

    /// A figure per column, as the dashboard's lists show them.
    init(process: ProcessEntry, figures: [String], columns: [ProcessColumn]) {
        self.process = process
        self.figures = figures
        self.columns = columns
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(process.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: "\(process.pid)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            if columns.isEmpty {
                Text(figures.first ?? "").monospacedDigit()
            } else {
                FigureColumns(figures: figures, columns: columns)
                    .monospacedDigit()
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.leading, indent)
        .padding(.trailing, trailing)
        .frame(height: 24)
    }
}

/// Sizes shared by the list's rows and header.
enum ProcessListMetrics {
    static let rowPadding: CGFloat = 12
    /// Where an app's name starts: past the chevron and icon.
    static let nameIndent: CGFloat = rowPadding + 10 + 8 + DashboardMetrics.iconSize + 8
}
