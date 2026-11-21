import SwiftUI

/// One metric as a ring: an arc in the metric's colour with a soft glow, over a track, with an
/// SF Symbol and a short label inside. The value sits below it.
public struct RingView: View {
    let symbol: String
    let label: String
    /// 0...1, or nil when there is no live value; then only the track shows.
    let fraction: Double?
    let color: Color
    let value: String
    let detail: String?

    public init(symbol: String, label: String, fraction: Double?, color: Color, value: String, detail: String? = nil) {
        self.symbol = symbol
        self.label = label
        self.fraction = fraction
        self.color = color
        self.value = value
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: 6) {
            ring
            VStack(spacing: 1) {
                Text(value)
                    .font(.ringValue)
                    .foregroundStyle(fraction == nil ? Theme.dimText : Theme.text)
                Text(detail ?? " ")
                    .font(.ringDetail)
                    .foregroundStyle(Theme.dimText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: Metrics.ringLineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, fraction)))
                    .stroke(color, style: StrokeStyle(lineWidth: Metrics.ringLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.75), radius: 4)
                    .shadow(color: color.opacity(0.35), radius: 9)
            }
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                Text(label)
                    .font(.ringLabel)
                    .tracking(0.3)
            }
            .foregroundStyle(Theme.text)
        }
        .frame(width: Metrics.ringDiameter, height: Metrics.ringDiameter)
    }
}
