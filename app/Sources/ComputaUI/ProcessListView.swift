import ComputaCore
import SwiftUI

/// The grouped process list in its rounded panel: one row per app with chevron, icon, name,
/// "+N" badge and value; expanded groups show their processes underneath.
struct ProcessListView: View {
    /// Already filtered and sorted.
    let groups: [ProcessGroup]
    let metric: ProcessMetric
    /// Shown as a last dim row when set (the memory tab only).
    let hidden: HiddenProcesses?
    @Binding var expanded: Set<String>
    let icons: any AppIconProviding
    /// Shown when no group matches the search.
    var emptyText = "No process matches."

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if metric == .memory, !groups.isEmpty {
                    MemoryColumnsHeader()
                }
                if groups.isEmpty {
                    Text(emptyText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dimText)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                ForEach(groups) { group in
                    GroupRow(group: group, metric: metric, isExpanded: expanded.contains(group.id), icon: icons.icon(for: group)) {
                        toggle(group)
                    }
                    if expanded.contains(group.id), group.processes.count > 1 {
                        ForEach(group.processes) { process in
                            ProcessRow(
                                process: process,
                                value: ProcessList.valueText(ProcessList.value(process, metric), metric),
                                total: ProcessList.totalText(footprint: process.memoryBytes, metric)
                            )
                        }
                    }
                }
                if let hidden {
                    HiddenProcessesRow(hidden: hidden)
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.automatic)
        .background(DashboardPanel())
    }

    private func toggle(_ group: ProcessGroup) {
        guard group.processes.count > 1 else { return }
        if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
    }
}

/// One app's row.
struct GroupRow: View {
    let group: ProcessGroup
    let metric: ProcessMetric
    let isExpanded: Bool
    let icon: AppIcon
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text.opacity(0.75))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 10)
                .opacity(group.processes.count > 1 ? 1 : 0)
            AppIconView(icon: icon)
            Text(group.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            if let badge = group.badge {
                CountBadge(text: badge)
            }
            Spacer(minLength: 8)
            Text(ProcessList.valueText(ProcessList.value(group, metric), metric))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            if let total = ProcessList.totalText(footprint: group.memoryBytes, metric) {
                TotalFigure(text: total, size: 12)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: DashboardMetrics.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(group.processes.count > 1 ? .isButton : [])
    }
}

/// One process inside an expanded group: name, pid and value, indented under the app's name.
struct ProcessRow: View {
    let process: ProcessEntry
    let value: String
    /// The footprint, in the memory list's second column. Nil where there is one figure.
    var total: String?
    /// Where the name starts: under the app's name by default.
    var indent: CGFloat = 14 + 10 + 10 + DashboardMetrics.iconSize + 10
    /// Where the value ends.
    var trailing: CGFloat = 14

    var body: some View {
        HStack(spacing: 8) {
            Text(process.name)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: "\(process.pid)")
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Theme.dimText)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.text.opacity(0.78))
            if let total {
                TotalFigure(text: total, size: 11)
            }
        }
        .padding(.leading, indent)
        .padding(.trailing, trailing)
        .frame(height: 24)
    }
}

/// The memory list's second column: the footprint, dimmer than the in-RAM figure beside it.
struct TotalFigure: View {
    static let width: CGFloat = 76

    let text: String
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size).monospacedDigit())
            .foregroundStyle(Theme.dimText)
            .lineLimit(1)
            .frame(width: Self.width, alignment: .trailing)
    }
}

/// Names the memory list's two columns and says why the second can exceed the RAM installed.
struct MemoryColumnsHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Total counts memory macOS has compressed or moved to swap, so it can exceed the RAM installed.")
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text("In RAM")
                .foregroundStyle(Theme.text.opacity(0.78))
            Text("Total")
                .frame(width: TotalFigure.width, alignment: .trailing)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(Theme.dimText)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

/// The dim last row on the memory tab: processes owned by root or other users, whose usage a
/// daemon running as the user cannot read. Only their number is shown.
struct HiddenProcessesRow: View {
    let hidden: HiddenProcesses

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Color.clear.frame(width: 10, height: 1)
            AppIconView(icon: .symbol("lock.fill"))
                .opacity(0.7)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text("Root and other users")
                        .font(.system(size: 13, weight: .medium))
                    CountBadge(text: "\(hidden.processCount) processes")
                }
                Text("Their usage can't be read unless computad runs as root.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.dimText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.text.opacity(0.55))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// The small "+N" count beside an app's name.
struct CountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.text.opacity(0.6))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.08)))
            .fixedSize()
    }
}

/// The rounded panel behind the lists, with a hairline edge.
struct DashboardPanel: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DashboardMetrics.panelRadius, style: .continuous)
            .fill(Theme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: DashboardMetrics.panelRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}
