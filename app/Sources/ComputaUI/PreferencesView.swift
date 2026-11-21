import ComputaCore
import SwiftUI

/// The settings, as a native grouped form: the machines to watch, and where the `rex`
/// command is.
public struct PreferencesView: View {
    @State private var form: MachineForm?
    let machines: [Machine]
    let editing: MachineEditing
    let storeProblem: String?
    let rexCommand: String
    let rexLookup: RexLookup
    let saveRexCommand: @MainActor (String) -> RexLookup

    /// - Parameters:
    ///   - machines: The list, This Mac first.
    ///   - editing: Adds, edits and removes machines.
    ///   - storeProblem: Why the list could not be stored, if it could not.
    ///   - rexCommand: The stored `rex` path; empty when it is found automatically.
    ///   - rexLookup: Where `rex` is now.
    ///   - saveRexCommand: Stores a `rex` path (blank clears it) and returns where `rex` is then.
    ///   - form: An open add/edit form, for snapshots.
    public init(
        machines: [Machine], editing: MachineEditing, storeProblem: String? = nil,
        rexCommand: String, rexLookup: RexLookup, saveRexCommand: @escaping @MainActor (String) -> RexLookup,
        form: MachineForm? = nil
    ) {
        _form = State(initialValue: form)
        self.machines = machines
        self.editing = editing
        self.storeProblem = storeProblem
        self.rexCommand = rexCommand
        self.rexLookup = rexLookup
        self.saveRexCommand = saveRexCommand
    }

    public var body: some View {
        Form {
            Section {
                AppSummaryRow(machineCount: machines.count)
            }
            MachinesSection(machines: machines, editing: editing, storeProblem: storeProblem, form: $form)
            RexCommandSection(current: rexCommand, lookup: rexLookup, save: saveRexCommand)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .frame(width: 500)
        .frame(minHeight: 420, idealHeight: 700)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }
}

/// The top of Preferences, like the Rex settings' server card: the app and what it watches.
struct AppSummaryRow: View {
    let machineCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.memory, Theme.sessions], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Computa")
                    .font(.headline)
                Text(machineCount == 1 ? "Watching this Mac" : "Watching \(machineCount) machines")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
