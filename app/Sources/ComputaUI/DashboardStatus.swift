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
                    Text(entry.label).foregroundStyle(Theme.dimText)
                    Text(entry.value).foregroundStyle(Theme.text.opacity(0.85))
                }
            }
            Spacer(minLength: 4)
            Text(headline)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.text)
        }
        .font(.system(size: 11).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, 4)
    }
}

/// Shown below the tabs until the first sample arrives.
struct ConnectingPanel: View {
    let endpoint: DaemonEndpoint
    var machine: MachineContext = .thisMacOnly

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.dimText)
            Text("Connecting…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(machine.isRemote
                ? "Waiting for computad on \(machine.name) through the tunnel."
                : "Waiting for computad at \(endpoint.description).")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(DashboardPanel())
    }
}
