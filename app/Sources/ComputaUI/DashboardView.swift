import ComputaCore
import SwiftUI

/// Stand-in for the phase 3 dashboard: host facts and the current numbers, in the theme.
public struct DashboardView: View {
    let state: ConnectionState
    let sample: SystemSample?
    let host: HostInfo?

    public init(state: ConnectionState, sample: SystemSample?, host: HostInfo?) {
        self.state = state
        self.sample = state.isConnected ? sample : nil
        self.host = host
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let sample {
                RingsSection(sample: sample)
                    .background(panel)
                facts(rows: numberRows(sample))
            } else if case .daemonNotRunning(let problem) = state {
                DaemonDownSection(problem: problem).background(panel)
            } else {
                Text("Connecting…").font(.rowLabel).foregroundStyle(Theme.dimText)
            }
            if let host { facts(rows: hostRows(host)) }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 480, alignment: .topLeading)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(host?.hostname ?? "Computa")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("The full dashboard arrives in phase 3.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText)
        }
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel)
    }

    private func facts(rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.0) { row in
                InfoRow(label: row.0, value: row.1, valueColor: Theme.dimText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(panel)
    }

    private func numberRows(_ sample: SystemSample) -> [(String, String)] {
        var rows = [
            ("CPU user / system", "\(Format.percent(sample.cpu.userPercent)) / \(Format.percent(sample.cpu.systemPercent))"),
            ("Swap", Format.memory(sample.memory.swapUsedBytes)),
            ("Network ↓ / ↑", "\(Format.rate(sample.network.receiveBytesPerSecond)) / \(Format.rate(sample.network.sendBytesPerSecond))"),
            ("Disk read / write", "\(Format.rate(sample.diskReadBytesPerSecond)) / \(Format.rate(sample.diskWriteBytesPerSecond))"),
        ]
        if let battery = sample.battery { rows.append(("Battery", Format.battery(battery))) }
        return rows
    }

    private func hostRows(_ host: HostInfo) -> [(String, String)] {
        [
            ("Chip", host.chip),
            ("Model", host.model),
            ("Cores", host.coreGroups.map { "\($0.coreCount) \($0.name)" }.joined(separator: " + ")),
            ("Memory", Format.memory(host.memoryTotalBytes)),
            ("System", host.osVersion),
            ("Daemon", "computad \(host.daemonVersion)"),
        ]
    }
}
