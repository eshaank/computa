import ComputaCore
import SwiftUI

/// The Net tab's interfaces: the totals, then each interface on one line with its first
/// address and rates. All addresses are in the tooltip.
struct NetworkPanel: View {
    let network: NetworkSample

    var body: some View {
        VStack(spacing: 0) {
            TotalsRow(
                label: "All physical interfaces",
                first: "↓ \(Format.rate(network.receiveBytesPerSecond))",
                second: "↑ \(Format.rate(network.sendBytesPerSecond))",
                color: Theme.network
            )
            ForEach(network.interfaces, id: \.name) { interface in
                PanelDivider()
                interfaceRow(interface)
            }
            if network.interfaces.isEmpty {
                PanelDivider()
                Text("No interface is up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
        }
        .padding(.vertical, 2)
        .background(DashboardPanel())
        .fixedSize(horizontal: false, vertical: true)
    }

    private func interfaceRow(_ interface: NetworkInterfaceSample) -> some View {
        HStack(spacing: 8) {
            Text(interface.name)
            Text(addressText(interface.addresses))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(interface.addresses.joined(separator: "\n"))
            Spacer(minLength: 8)
            Text("↓ \(Format.rate(interface.receiveBytesPerSecond))")
                .frame(minWidth: 76, alignment: .trailing)
            Text("↑ \(Format.rate(interface.sendBytesPerSecond))")
                .foregroundStyle(Theme.network.opacity(0.7))
                .frame(minWidth: 76, alignment: .trailing)
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(Theme.network)
        .padding(.horizontal, 12)
        .frame(minHeight: 28)
    }

    /// The first address and how many more: "192.168.1.42 +1".
    private func addressText(_ addresses: [String]) -> String {
        guard let first = addresses.first else { return "" }
        return addresses.count > 1 ? "\(first) +\(addresses.count - 1)" : first
    }
}

/// The Disk tab's list: the activity totals, then each volume with a used/total bar.
struct DiskPanel: View {
    let sample: SystemSample

    var body: some View {
        FittingPanel {
            VStack(spacing: 0) {
                TotalsRow(
                    label: "All disks",
                    first: "Read \(Format.rate(sample.diskReadBytesPerSecond))",
                    second: "Write \(Format.rate(sample.diskWriteBytesPerSecond))",
                    color: Theme.disk
                )
                ForEach(sample.volumes, id: \.mountPoint) { volume in
                    PanelDivider()
                    VolumeRow(volume: volume)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct VolumeRow: View {
    let volume: VolumeSample

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(volume.name)
                    .font(.body)
                Text(volume.mountPoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(Format.storageUsage(used: volume.usedBytes, total: volume.totalBytes))
                    .font(.callout.monospacedDigit())
            }
            UsageBar(fraction: volume.usedPercent / 100, color: Theme.disk)
            HStack {
                Text("\(Format.percent(volume.usedPercent)) used")
                Spacer()
                Text("\(Format.storage(volume.availableBytes)) available")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// A thin track with a glowing fill.
struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, fraction))))
                    .glow(color)
            }
        }
        .frame(height: 6)
    }
}

/// The first row of the Net and Disk lists: a label and two figures.
struct TotalsRow: View {
    let label: String
    let first: String
    let second: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(first)
                .frame(minWidth: 76, alignment: .trailing)
            Text(second).opacity(0.7)
                .frame(minWidth: 76, alignment: .trailing)
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
    }
}

/// A panel as tall as its content, which scrolls when the window is too short for it.
struct FittingPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .vertical) {
                panel(content)
                panel(ScrollView { content })
            }
            Spacer(minLength: 0)
        }
    }

    private func panel(_ inner: some View) -> some View {
        inner
            .background(DashboardPanel())
            .clipShape(RoundedRectangle(cornerRadius: DashboardMetrics.panelRadius, style: .continuous))
    }
}

struct PanelDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 12)
    }
}
