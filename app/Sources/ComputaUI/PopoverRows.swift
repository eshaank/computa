import SwiftUI

/// A row with a label on the left and a value on the right.
struct InfoRow: View {
    let label: String
    let value: String
    var detail: String?
    var valueColor: Color = Theme.text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.rowLabel)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            Text(value)
                .font(.rowValue)
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .frame(minHeight: Metrics.rowHeight)
    }
}

/// A row with a label on the left and a switch on the right, as in the reference.
struct ToggleRow: View {
    let label: String
    let isOn: Bool
    var message: String?
    let onChange: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { isOn }, set: { newValue in onChange(newValue) })) {
                Text(label)
                    .font(.rowLabel)
                    .foregroundStyle(Theme.text)
            }
            .toggleStyle(ThemeSwitchStyle())
            if let message {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.warning)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: Metrics.rowHeight)
    }
}

/// A switch drawn in the theme's colours. Drawn by hand so it looks the same in the app and in
/// offscreen snapshots.
struct ThemeSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 8)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Theme.accent : Theme.track)
                    .shadow(color: configuration.isOn ? Theme.accent.opacity(0.45) : .clear, radius: 5)
                Capsule()
                    .fill(Color(hex: 0xEDEBF7))
                    .frame(width: 26, height: 19)
                    .padding(2.5)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
            .frame(width: 50, height: 24)
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            .contentShape(Capsule())
            .onTapGesture { configuration.isOn.toggle() }
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// A plain text button that dims while pressed.
struct ThemeButtonStyle: ButtonStyle {
    var color: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rowLabel)
            .foregroundStyle(color.opacity(configuration.isPressed ? 0.5 : 1))
            .contentShape(Rectangle())
    }
}

/// A thin line between popover sections, edge to edge as in the reference.
struct SectionDivider: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }
}
