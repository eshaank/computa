import ComputaCore
import SwiftUI

/// CPU, memory and startup disk as three rings. Without a sample only the tracks show.
struct RingsSection: View {
    let sample: SystemSample?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ring(symbol: "cpu", label: "CPU", percent: sample?.cpu.usagePercent, color: Theme.cpu, detail: nil)
            ring(
                symbol: "memorychip", label: "MEM", percent: sample?.memory.usedPercent, color: Theme.memory,
                detail: sample.map { Format.memoryUsage(used: $0.memory.usedBytes, total: $0.memory.totalBytes) }
            )
            ring(
                symbol: "internaldrive", label: "DISK", percent: sample.map { $0.startupVolume?.usedPercent ?? 0 },
                color: Theme.disk,
                detail: sample?.startupVolume.map { Format.storageUsage(used: $0.usedBytes, total: $0.totalBytes) }
            )
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .padding(.horizontal, 8)
    }

    private func ring(symbol: String, label: String, percent: Double?, color: Color, detail: String?) -> some View {
        RingView(
            symbol: symbol,
            label: label,
            fraction: percent.map(Format.ringFraction),
            color: color,
            value: percent.map(Format.percent) ?? "–",
            detail: detail
        )
        .frame(maxWidth: .infinity)
    }
}

/// Machine, network, battery, memory pressure and Claude Code rows, or a connecting note.
/// With more than one machine, the machine row is the switcher and shows in every state.
struct StatusRows: View {
    let content: PopoverContent
    var switching: MachineSwitching = .none

    var body: some View {
        VStack(spacing: 0) {
            if content.machine.showsSwitcher, content.sample == nil {
                MachineSwitcherRow(machine: content.machine, value: nil, detail: connectingText, switching: switching)
            } else if content.sample == nil, content.machine.isRemote {
                InfoRow(label: "Connecting…", value: content.machine.name, detail: connectingText, valueColor: .secondary)
            }
            if let sample = content.sample {
                machineRow(time: sample.time)
                InfoRow(
                    label: "Network",
                    value: "↓ \(Format.rate(sample.network.receiveBytesPerSecond))  ↑ \(Format.rate(sample.network.sendBytesPerSecond))",
                    valueColor: Theme.network
                )
                if let battery = sample.battery {
                    InfoRow(label: "Battery", value: Format.battery(battery))
                }
                if let pressure = pressureText(sample.memory.pressure) {
                    InfoRow(label: "Memory Pressure", value: pressure, valueColor: Theme.warning)
                }
                if let claude = content.claudeSummary {
                    InfoRow(label: "Claude Code", value: claude, detail: content.claudeMemoryNote, valueColor: Theme.sessions)
                        .help(PopoverContent.claudeMemoryHelp)
                }
            } else if !content.machine.showsSwitcher, !content.machine.isRemote {
                InfoRow(label: "Connecting…", value: content.endpoint.description, valueColor: .secondary)
            }
        }
        .padding(.horizontal, Metrics.sidePadding)
        .padding(.vertical, 6)
    }

    /// What the machine row says while there are no numbers yet.
    private var connectingText: String {
        if content.machine.pendingTunnel != nil, let remote = content.machine.remote {
            return "Connecting to \(remote.destination)…"
        }
        return content.machine.isRemote ? "Waiting for computad…" : "Connecting to \(content.endpoint)…"
    }

    @ViewBuilder
    private func machineRow(time: Date) -> some View {
        if content.machine.showsSwitcher {
            MachineSwitcherRow(
                machine: content.machine, value: "up \(content.host.map { Format.uptime(since: $0.bootTime, now: time) } ?? "–")",
                detail: content.host?.chip ?? "", switching: switching
            )
        } else if let host = content.host {
            InfoRow(
                label: host.hostname,
                value: "up \(Format.uptime(since: host.bootTime, now: time))",
                detail: host.chip,
                valueColor: .secondary
            )
        }
    }

    private func pressureText(_ pressure: MemoryPressure) -> String? {
        switch pressure {
        case .warning: "Warning"
        case .critical: "Critical"
        case .normal, .unknown: nil
        }
    }
}

/// Shown instead of the numbers when the daemon cannot be reached.
struct DaemonDownSection: View {
    let problem: DaemonProblem

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.largeTitle.weight(.light))
                .foregroundStyle(Theme.warning)
                .glow(Theme.warning)
            Text(title)
                .font(.headline)
            Text(problem.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(problem.kind == .unsupported
                ? "Update computad; Computa picks it up by itself."
                : "Computa will reconnect by itself as soon as it answers.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Metrics.sidePadding)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        switch problem.kind {
        case .unreachable: "Daemon not running"
        case .unsupported: "Daemon needs an update"
        case .streamEnded, .other: "Daemon not responding"
        }
    }
}
