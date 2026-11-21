import ComputaCore
import SwiftUI

/// A tab's process section: the list, or on the Net tab why there are no rates yet, and the
/// Net tab's note on how its rates relate to the chart.
struct ProcessPanel: View {
    let snapshot: ProcessSnapshot
    let metric: ProcessMetric
    let query: String
    @Binding var expanded: Set<String>
    let icons: any AppIconProviding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let availability = TrafficAvailability(snapshot.network)
            if metric == .network, availability != .available {
                TrafficStatusView(availability: availability)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DashboardPanel())
            } else {
                list
            }
            if metric == .network {
                Text(FigureExplanations.networkCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var list: some View {
        let reported = snapshot.reportsResidentSize
        let blank = query.trimmingCharacters(in: .whitespaces).isEmpty
        return ProcessListView(
            groups: ProcessList.visible(snapshot.groups, query: query, metric: metric, residentReported: reported),
            metric: metric,
            residentReported: reported,
            hidden: metric == .memory && blank ? snapshot.hidden : nil,
            expanded: $expanded,
            icons: icons
        )
    }
}

/// The grouped process list in its rounded panel, under a header naming its columns: one row
/// per app with chevron, icon, name, "+N" badge and figures; expanded groups show their
/// processes underneath.
struct ProcessListView: View {
    /// Already filtered and sorted.
    let groups: [ProcessGroup]
    let metric: ProcessMetric
    /// False when the daemon reports no resident sizes; see `ProcessSnapshot.reportsResidentSize`.
    var residentReported = true
    /// Shown as a last dim row when set (the memory tab only).
    let hidden: HiddenProcesses?
    @Binding var expanded: Set<String>
    let icons: any AppIconProviding
    /// Shown when no group matches the search.
    var emptyText = "No process matches."

    private var columns: [ProcessColumn] { ProcessColumn.columns(metric) }

    var body: some View {
        VStack(spacing: 0) {
            ProcessColumnsHeader(metric: metric, columns: columns, residentReported: residentReported)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if groups.isEmpty {
                        Text(emptyText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    ForEach(groups) { group in
                        rows(group)
                    }
                    if let hidden {
                        HiddenProcessesRow(hidden: hidden)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.automatic)
        }
        .background(DashboardPanel())
        .clipShape(RoundedRectangle(cornerRadius: DashboardMetrics.panelRadius, style: .continuous))
    }

    @ViewBuilder
    private func rows(_ group: ProcessGroup) -> some View {
        GroupRow(
            group: group, figures: ProcessColumn.figures(group, metric, residentReported: residentReported),
            columns: columns, isExpanded: expanded.contains(group.id), icon: icons.icon(for: group)
        ) {
            toggle(group)
        }
        if expanded.contains(group.id), group.processes.count > 1 {
            ForEach(group.processes) { process in
                ProcessRow(
                    process: process,
                    figures: ProcessColumn.figures(process, metric, residentReported: residentReported),
                    columns: columns
                )
            }
        }
    }

    private func toggle(_ group: ProcessGroup) {
        guard group.processes.count > 1 else { return }
        if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
    }
}

/// The dim last row on the memory tab: processes owned by root or other users, whose usage a
/// daemon running as the user cannot read. Only their number is shown.
struct HiddenProcessesRow: View {
    let hidden: HiddenProcesses

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Color.clear.frame(width: 10, height: 1)
            AppIconView(icon: .symbol("lock.fill"))
                .opacity(0.7)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Root and other users")
                    CountBadge(text: "\(hidden.processCount) processes")
                }
                Text("Their usage can't be read unless computad runs as root.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, ProcessListMetrics.rowPadding)
        .padding(.vertical, 8)
    }
}

/// The small "+N" count beside an app's name.
struct CountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(.quaternary))
            .fixedSize()
    }
}

/// The rounded panel behind the lists: a faint fill on the window background with a hairline
/// edge, like a grouped form's sections.
struct DashboardPanel: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DashboardMetrics.panelRadius, style: .continuous)
            .fill(.quinary)
            .overlay(
                RoundedRectangle(cornerRadius: DashboardMetrics.panelRadius, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )
    }
}
