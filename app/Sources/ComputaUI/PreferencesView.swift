import ComputaCore
import SwiftUI

/// The settings: the machines to watch, and where the `rex` command is.
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
        VStack(alignment: .leading, spacing: 18) {
            MachinesSection(machines: machines, editing: editing, storeProblem: storeProblem, form: $form)
            Rectangle().fill(Theme.divider).frame(height: 1)
            RexCommandSection(current: rexCommand, lookup: rexLookup, save: saveRexCommand)
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }
}
