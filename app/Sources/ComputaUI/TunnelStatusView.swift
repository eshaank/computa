import ComputaCore
import SwiftUI

/// A remote machine's tunnel while it is not up: connecting, or unreachable with the reason.
/// Shown instead of the numbers, in the popover and the dashboard.
struct TunnelStatusView: View {
    let machine: MachineContext
    let state: TunnelState

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(tint)
                .glow(tint, isOn: isUnreachable)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(index == 0 ? Theme.text.opacity(0.8) : Theme.dimText)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Metrics.sidePadding)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private var isUnreachable: Bool {
        if case .unreachable = state { true } else { false }
    }

    private var destination: String { machine.remote?.destination ?? machine.name }

    private var symbol: String {
        isUnreachable ? "network.slash" : "point.3.connected.trianglepath.dotted"
    }

    private var tint: Color { isUnreachable ? Theme.warning : Theme.dimText }

    private var title: String {
        isUnreachable ? "\(machine.name) unreachable" : "Connecting to \(machine.name)…"
    }

    private var lines: [String] {
        switch state {
        case .unreachable(let reason):
            [reason, "Computa keeps trying and reconnects by itself."]
        case .connecting, .connected:
            ["Opening an SSH tunnel to \(destination)."]
        }
    }
}
