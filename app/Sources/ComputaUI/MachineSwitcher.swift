import ComputaCore
import SwiftUI

/// What the machine switcher does: select a machine, and optionally open Preferences.
public struct MachineSwitching: Sendable {
    public var select: @MainActor @Sendable (String) -> Void
    /// Nil hides "Manage Machines…".
    public var manage: (@MainActor @Sendable () -> Void)?

    public init(
        select: @escaping @MainActor @Sendable (String) -> Void, manage: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.select = select
        self.manage = manage
    }

    /// Does nothing; for previews and snapshots.
    public static let none = MachineSwitching(select: { _ in })
}

/// A menu of the machines with the shown one ticked, opened from `label`.
struct MachineMenu<Label: View>: View {
    let machine: MachineContext
    let switching: MachineSwitching
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            ForEach(machine.choices) { choice in
                Toggle(choice.name, isOn: Binding(
                    get: { choice.id == machine.selectedID },
                    set: { if $0 { switching.select(choice.id) } }
                ))
            }
            if let manage = switching.manage {
                Divider()
                Button("Manage Machines…") { manage() }
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Machine: \(machine.name)")
    }
}

/// The machine's name with the up-down chevron that says it opens a menu.
struct MachineTitle: View {
    let name: String
    var font: Font = .rowLabel

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(font)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Theme.dimText)
        }
        .contentShape(Rectangle())
    }
}

/// The popover's machine row as a menu: name, what it is or how it stands, and uptime.
struct MachineSwitcherRow: View {
    let machine: MachineContext
    /// The value on the right, for example "up 3d 4h".
    let value: String?
    let detail: String
    let switching: MachineSwitching

    var body: some View {
        MachineMenu(machine: machine, switching: switching) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    MachineTitle(name: machine.name)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                if let value {
                    Text(value)
                        .font(.rowValue)
                        .foregroundStyle(Theme.dimText)
                        .lineLimit(1)
                        .fixedSize()
                        .layoutPriority(2)
                }
            }
            .frame(minHeight: Metrics.rowHeight)
            .contentShape(Rectangle())
        }
    }
}

/// The menu's items drawn as a view, for snapshots: a real menu only exists while it is open.
public struct MachineMenuPreview: View {
    let machine: MachineContext
    let showsManage: Bool

    public init(machine: MachineContext, showsManage: Bool = true) {
        self.machine = machine
        self.showsManage = showsManage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(machine.choices) { choice in
                item(choice.name, ticked: choice.id == machine.selectedID)
            }
            if showsManage {
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.vertical, 5).padding(.horizontal, 10)
                item("Manage Machines…", ticked: false)
            }
        }
        .padding(5)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.16).opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        )
        .environment(\.colorScheme, .dark)
    }

    private func item(_ title: String, ticked: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .opacity(ticked ? 1 : 0)
            Text(title).font(.system(size: 13))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.white.opacity(0.9))
        .padding(.horizontal, 8)
        .frame(height: 22)
    }
}
