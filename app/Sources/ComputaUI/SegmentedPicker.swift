import ComputaCore
import SwiftUI

/// A segmented control drawn by hand: a dark capsule with a hairline edge and the selected
/// segment filled. The dashboard's own controls are native `Picker`s now; only the Sessions
/// tab still uses this.
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
