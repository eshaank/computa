import ComputaCore
import SwiftUI

/// A segmented control drawn by hand, as in the reference: a dark capsule with a hairline edge
/// and the selected segment filled. Drawn by hand so the app and offscreen snapshots match.
struct SegmentedPicker<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    /// The fill of the selected segment.
    let tint: (Item) -> Color
    var segmentWidth: CGFloat = 62
    var height: CGFloat = DashboardMetrics.tabHeight
    var font: Font = .system(size: 13, weight: .semibold)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                segment(item)
            }
        }
        .padding(2)
        .background(OutlinedCapsule(fill: Theme.panel))
    }

    private func segment(_ item: Item) -> some View {
        let selected = item == selection
        return Text(title(item))
            .font(font)
            .foregroundStyle(selected ? Theme.panel : Theme.text.opacity(0.85))
            .frame(width: segmentWidth, height: height - 4)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: (height - 4) / 2, style: .continuous)
                        .fill(tint(item))
                        .glow(tint(item))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selection = item }
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(title(item))
    }
}

/// The dashboard's tab control.
struct DashboardTabBar: View {
    @Binding var tab: DashboardTab

    var body: some View {
        SegmentedPicker(
            items: DashboardTab.allCases, selection: $tab, title: \.title, tint: \.color,
            segmentWidth: 68
        )
    }
}

/// The small control choosing the chart's time window.
struct RangePicker: View {
    @Binding var range: HistoryRange
    let tint: Color

    var body: some View {
        SegmentedPicker(
            items: HistoryRange.allCases, selection: $range, title: \.title, tint: { _ in tint },
            segmentWidth: 34, height: 22, font: .system(size: 11, weight: .semibold)
        )
    }
}
