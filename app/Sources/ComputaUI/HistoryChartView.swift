import ComputaCore
import SwiftUI

/// The bar chart at the top of each tab, styled like the reference: bars that fill the panel's
/// width and touch its bottom edge, dashed guide lines, and each guide's value in a pill on the
/// left. Bars glow softly in the tab's colour.
struct HistoryChartView: View {
    let model: ChartModel
    let tab: DashboardTab
    /// Shown in the middle when there are no bars, for example while loading.
    var message: String?

    var body: some View {
        GeometryReader { proxy in
            let layout = ChartLayout(size: proxy.size, mirrored: model.isMirrored)
            ZStack(alignment: .topLeading) {
                guideLines(layout)
                bars(layout)
                    .glow(tab.color)
                // Without bars the scale is a placeholder, so its values are not shown.
                if !model.bars.isEmpty { pills(layout) }
                if model.bars.isEmpty, let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .background(Theme.panel.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: DashboardMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardMetrics.panelRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tab.title) history chart")
    }

    /// Where each guide's line sits: above the baseline, and below it on two-series charts.
    private func guidePositions(_ layout: ChartLayout) -> [(id: String, y: CGFloat, label: String)] {
        model.scale.guides.flatMap { guide in
            let fraction = model.scale.fraction(guide.value)
            var positions = [(id: "up\(guide.value)", y: layout.y(up: fraction), label: guide.label)]
            if model.isMirrored {
                positions.append((id: "down\(guide.value)", y: layout.y(down: fraction), label: guide.label))
            }
            return positions
        }
    }

    private func guideLines(_ layout: ChartLayout) -> some View {
        Canvas { context, size in
            let dash = StrokeStyle(lineWidth: 1, dash: [4, 4])
            for guide in guidePositions(layout) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: guide.y))
                line.addLine(to: CGPoint(x: size.width, y: guide.y))
                context.stroke(line, with: .color(Color.white.opacity(0.22)), style: dash)
            }
            if model.isMirrored {
                let baseline = Path(CGRect(x: 0, y: layout.baseline - 0.5, width: size.width, height: 1))
                context.fill(baseline, with: .color(Color.white.opacity(0.18)))
            }
        }
    }

    private func bars(_ layout: ChartLayout) -> some View {
        Canvas { context, size in
            let slot = size.width / CGFloat(model.slotCount)
            let width = max(1, slot * 0.8)
            let firstSlot = model.slotCount - model.bars.count
            for (index, bar) in model.bars.enumerated() {
                let x = CGFloat(firstSlot + index) * slot + (slot - width) / 2
                draw(bar.parts, colors: tab.partColors, at: x, width: width, upward: true, layout: layout, in: &context)
                if model.isMirrored {
                    draw(bar.mirroredParts, colors: [tab.mirroredColor], at: x, width: width, upward: false, layout: layout, in: &context)
                }
            }
        }
    }

    /// Draws one stack of parts from the baseline, with rounded ends away from it. A stack of one
    /// part fades darker toward the baseline, like the darker lower part in the reference.
    private func draw(
        _ parts: [Double], colors: [Color], at x: CGFloat, width: CGFloat, upward: Bool,
        layout: ChartLayout, in context: inout GraphicsContext
    ) {
        let height = layout.half * CGFloat(model.scale.fraction(parts.reduce(0, +)))
        guard height > 0.25 else { return }
        let whole = CGRect(x: x, y: upward ? layout.baseline - height : layout.baseline, width: width, height: height)
        let radius = min(width / 2, 2)
        let shape = upward
            ? UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius).path(in: whole)
            : UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius).path(in: whole)
        context.drawLayer { layer in
            layer.clip(to: shape)
            if parts.count == 1, let color = colors.first {
                let far = CGPoint(x: x, y: upward ? whole.minY : whole.maxY)
                let near = CGPoint(x: x, y: layout.baseline)
                layer.fill(shape, with: .linearGradient(Gradient(colors: [color, color.opacity(0.55)]), startPoint: far, endPoint: near))
                return
            }
            var offset: CGFloat = 0
            for (index, part) in parts.enumerated() {
                let partHeight = layout.half * CGFloat(model.scale.fraction(part))
                let y = upward ? layout.baseline - offset - partHeight : layout.baseline + offset
                layer.fill(Path(CGRect(x: x, y: y, width: width, height: partHeight)), with: .color(colors[min(index, colors.count - 1)]))
                offset += partHeight
            }
        }
    }

    private func pills(_ layout: ChartLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(guidePositions(layout), id: \.id) { guide in
                GuidePill(text: guide.label)
                    .alignmentGuide(.top) { $0[VerticalAlignment.center] - guide.y }
                    .alignmentGuide(.leading) { _ in -8 }
            }
        }
    }
}

/// Where the baseline is and how tall each half of the chart is.
struct ChartLayout {
    /// Room above the top guide, so its pill fits inside the panel.
    static let topInset: CGFloat = 18

    let baseline: CGFloat
    /// The height that the top of the scale reaches from the baseline.
    let half: CGFloat

    init(size: CGSize, mirrored: Bool) {
        if mirrored {
            half = max(0, (size.height - 2 * Self.topInset) / 2)
            baseline = Self.topInset + half
        } else {
            half = max(0, size.height - Self.topInset)
            baseline = size.height
        }
    }

    func y(up fraction: Double) -> CGFloat { baseline - half * CGFloat(fraction) }
    func y(down fraction: Double) -> CGFloat { baseline + half * CGFloat(fraction) }
}

/// A guide's value in a pill, as in the reference.
struct GuidePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.chartAxis)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(OutlinedCapsule(fill: Color(hex: 0x3A3E52).opacity(0.92), edge: Color.white.opacity(0.22)))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .fixedSize()
    }
}
