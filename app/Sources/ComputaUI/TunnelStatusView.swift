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
                .font(.largeTitle.weight(.light))
                .foregroundStyle(tint)
                .glow(tint, isOn: isUnreachable)
            Text(title)
                .font(.headline)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(index == 0 ? .callout : .footnote)
                    .foregroundStyle(index == 0 ? .secondary : .tertiary)
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

    private var tint: Color { isUnreachable ? Theme.warning : .secondary }

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
