import SwiftUI

/// A row with a label on the left and a value on the right.
struct InfoRow: View {
    let label: String
    let value: String
    var detail: String?
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            // The value never truncates; the label gives way first.
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minHeight: Metrics.rowHeight)
    }
}

/// A row with a label on the left and a native switch on the right, as in the reference.
struct ToggleRow: View {
    let label: String
    let isOn: Bool
    /// A dim line under the label.
    var detail: String?
    var message: String?
    let onChange: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.body)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Toggle(label, isOn: Binding(get: { isOn }, set: { newValue in onChange(newValue) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.accent)
            }
            if let message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(Theme.warning)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: Metrics.rowHeight)
    }
}

/// A thin line between popover sections, edge to edge as in the reference.
struct SectionDivider: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }
}
