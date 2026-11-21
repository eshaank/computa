import ComputaCore
import SwiftUI

/// Each tab's colours, and the names of its chart parts for the legend.
extension DashboardTab {
    /// The tab's theme colour.
    var color: Color { Color(hex: hex) }

    /// Colours of the chart's stacked parts, bottom first: darker shades below, the full colour
    /// on top, as in the reference.
    var partColors: [Color] {
        switch self {
        case .cpu: [Color(hex: blend(hex, 0x20222E, 0.45)), color]
        case .memory: [Color(hex: blend(0xB696F7, 0x20222E, 0.5)), Color(hex: blend(0xB696F7, 0x20222E, 0.22)), Theme.memoryLight]
        case .network, .disk: [color]
        }
    }

    /// The colour of the parts below the baseline on two-series charts.
    var mirroredColor: Color { Color(hex: blend(hex, 0x20222E, 0.4)) }

    /// The theme colours as numbers, so shades can be mixed from them.
    private var hex: UInt32 {
        switch self {
        case .cpu: 0x4DF08A
        case .memory: 0xB696F7
        case .network: 0x90ECF6
        case .disk: 0xF5F28A
        }
    }
}

/// One entry in the legend under the chart.
struct LegendEntry: Identifiable {
    let label: String
    let value: String
    let color: Color

    var id: String { label }
}

extension DashboardTab {
    /// Legend entries with the live values, top part of the stack first. Values show as "–"
    /// without a live sample.
    func legend(_ sample: SystemSample?) -> [LegendEntry] {
        let colors = partColors
        switch self {
        case .cpu:
            return [
                LegendEntry(label: "User", value: sample.map { Format.percent($0.cpu.userPercent) } ?? "–", color: colors[1]),
                LegendEntry(label: "System", value: sample.map { Format.percent($0.cpu.systemPercent) } ?? "–", color: colors[0]),
            ]
        case .memory:
            return [
                LegendEntry(label: "App", value: sample.map { Format.memory($0.memory.appBytes) } ?? "–", color: colors[2]),
                LegendEntry(label: "Compressed", value: sample.map { Format.memory($0.memory.compressedBytes) } ?? "–", color: colors[1]),
                LegendEntry(label: "Wired", value: sample.map { Format.memory($0.memory.wiredBytes) } ?? "–", color: colors[0]),
            ]
        case .network:
            return [
                LegendEntry(label: "↓ In", value: sample.map { Format.rate($0.network.receiveBytesPerSecond) } ?? "–", color: color),
                LegendEntry(label: "↑ Out", value: sample.map { Format.rate($0.network.sendBytesPerSecond) } ?? "–", color: mirroredColor),
            ]
        case .disk:
            return [
                LegendEntry(label: "Read", value: sample.map { Format.rate($0.diskReadBytesPerSecond) } ?? "–", color: color),
                LegendEntry(label: "Write", value: sample.map { Format.rate($0.diskWriteBytesPerSecond) } ?? "–", color: mirroredColor),
            ]
        }
    }

    /// The headline number for the tab, shown at the right of the legend.
    func headline(_ sample: SystemSample?) -> String {
        guard let sample else { return "–" }
        switch self {
        case .cpu: return Format.percent(sample.cpu.usagePercent)
        case .memory: return Format.memory(sample.memory.usedBytes)
        case .network, .disk: return ""
        }
    }
}

/// Mixes `color` toward `base` by `amount` (0 keeps `color`, 1 gives `base`), per channel.
func blend(_ color: UInt32, _ base: UInt32, _ amount: Double) -> UInt32 {
    func channel(_ shift: UInt32) -> UInt32 {
        let a = Double((color >> shift) & 0xFF)
        let b = Double((base >> shift) & 0xFF)
        return UInt32((a + (b - a) * amount).rounded()) << shift
    }
    return channel(16) | channel(8) | channel(0)
}

/// Sizes for the dashboard, from the reference screenshot (a 2x image, so pixels / 2, scaled to
/// the wider window).
enum DashboardMetrics {
    static let defaultSize = CGSize(width: 460, height: 760)
    static let minimumSize = CGSize(width: 400, height: 560)
    static let sidePadding: CGFloat = 14
    static let panelRadius: CGFloat = 16
    static let chartHeight: CGFloat = 200
    static let tabHeight: CGFloat = 30
    static let searchHeight: CGFloat = 38
    static let rowHeight: CGFloat = 32
    static let iconSize: CGFloat = 20
}

/// A capsule with a hairline edge. A stroked `Capsule` gets stray vertical ticks at its ends
/// when an `NSHostingView` draws itself offscreen, so this draws a circular rounded rectangle
/// with a plain stroke instead, which looks the same.
struct OutlinedCapsule: View {
    let fill: Color
    var edge: Color = Color.white.opacity(0.10)

    var body: some View {
        GeometryReader { proxy in
            let radius = max(0, proxy.size.height / 2 - 0.5)
            RoundedRectangle(cornerRadius: radius, style: .circular)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .circular)
                        .stroke(edge, lineWidth: 1)
                        .padding(0.5)
                )
        }
    }
}
