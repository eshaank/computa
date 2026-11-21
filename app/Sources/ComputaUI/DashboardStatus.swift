import ComputaCore
import SwiftUI

/// Colour keys for the chart's parts with their live values, and the tab's headline number.
struct ChartLegend: View {
    let entries: [LegendEntry]
    let headline: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(entries) { entry in
                HStack(spacing: 5) {
                    Circle().fill(entry.color).frame(width: 7, height: 7)
                    Text(entry.label).foregroundStyle(.secondary)
                    Text(entry.value)
                }
            }
            Spacer(minLength: 4)
            Text(headline)
                .font(.callout.weight(.medium).monospacedDigit())
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, 4)
    }
}

/// The Mem tab's second legend line: what the compressor holds, and swap. Both explain why
/// the Footprint column can add up to more than the RAM installed.
struct MemoryLegendDetail: View {
    let memory: MemorySample

    var body: some View {
        HStack(spacing: 12) {
            figure("Compressor", MemoryLegend.compressed(memory))
                .help("RAM the compressor occupies, and how much data it holds once expanded.")
            figure("Swap", MemoryLegend.swap(memory))
                .help("Memory moved out to disk, of the swap space macOS has set aside.")
            Spacer(minLength: 0)
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, 4)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

/// Shown below the toolbar until the first sample arrives.
struct ConnectingPanel: View {
    let endpoint: DaemonEndpoint
    var machine: MachineContext = .thisMacOnly

    var body: some View {
        ContentUnavailableView {
            Label("Connecting…", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            Text(machine.isRemote
                ? "Waiting for computad on \(machine.name) through the tunnel."
                : "Waiting for computad at \(endpoint.description).")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
