import ComputaCore
import SwiftUI

/// The Net tab's list: the totals, then each interface with its addresses and rates.
struct NetworkPanel: View {
    let network: NetworkSample

    var body: some View {
        FittingPanel {
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
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dimText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func interfaceRow(_ interface: NetworkInterfaceSample) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(interface.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                ForEach(interface.addresses, id: \.self) { address in
                    Text(address)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("↓ \(Format.rate(interface.receiveBytesPerSecond))")
                Text("↑ \(Format.rate(interface.sendBytesPerSecond))")
                    .foregroundStyle(Theme.network.opacity(0.7))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.network)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(volume.mountPoint)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dimText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(Format.storageUsage(used: volume.usedBytes, total: volume.totalBytes))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.text)
            }
            UsageBar(fraction: volume.usedPercent / 100, color: Theme.disk)
            HStack {
                Text("\(Format.percent(volume.usedPercent)) used")
                Spacer()
                Text("\(Format.storage(volume.availableBytes)) available")
            }
            .font(.system(size: 10.5).monospacedDigit())
            .foregroundStyle(Theme.dimText)
        }
        .padding(.horizontal, 14)
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
                    .shadow(color: color.opacity(0.5), radius: 4)
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Text(first)
            Text(second).opacity(0.7)
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
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
        Rectangle().fill(Theme.divider).frame(height: 1).padding(.horizontal, 14)
    }
}
