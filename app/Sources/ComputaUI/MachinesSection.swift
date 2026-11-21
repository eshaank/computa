import ComputaCore
import SwiftUI

/// What Preferences can do to the machine list. Each call checks its input and throws a
/// sentence for the form when it is wrong.
public struct MachineEditing: Sendable {
    /// Adds a remote machine (id nil) or replaces one's settings.
    public var save: @MainActor @Sendable (MachineDraft, String?) throws(MachineValidationError) -> Machine
    public var saveThisMacAddress: @MainActor @Sendable (String) throws(MachineValidationError) -> DaemonEndpoint
    public var remove: @MainActor @Sendable (String) throws(MachineValidationError) -> Void

    public init(
        save: @escaping @MainActor @Sendable (MachineDraft, String?) throws(MachineValidationError) -> Machine,
        saveThisMacAddress: @escaping @MainActor @Sendable (String) throws(MachineValidationError) -> DaemonEndpoint,
        remove: @escaping @MainActor @Sendable (String) throws(MachineValidationError) -> Void
    ) {
        self.save = save
        self.saveThisMacAddress = saveThisMacAddress
        self.remove = remove
    }
}

/// The Machines section of the form: the list with Edit and Remove, Add Machine, and the
/// add/edit form as its own section below.
struct MachinesSection: View {
    let machines: [Machine]
    let editing: MachineEditing
    /// Why the list could not be stored, if it could not.
    let storeProblem: String?
    @Binding var form: MachineForm?
    @State private var pendingRemoval: Machine?
    @State private var removeError: String?

    var body: some View {
        Section {
            ForEach(machines) { machine in
                row(machine)
            }
            if form == nil {
                Button("Add Machine…") { form = MachineForm(target: .add) }
            }
        } header: {
            Text("Machines")
        } footer: {
            if let problem = removeError ?? storeProblem {
                Text(problem)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert(
            "Remove \(pendingRemoval?.name ?? "machine")?", isPresented: removalShown, presenting: pendingRemoval
        ) { machine in
            Button("Remove", role: .destructive) { remove(machine) }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { _ in
            Text("Computa stops watching it. Nothing on that Mac changes.")
        }
        if let form = Binding($form) {
            MachineFormView(form: form, onCancel: { self.form = nil }, onSave: save)
        }
    }

    private func row(_ machine: Machine) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                Button("Edit") { form = .editing(machine) }
                if !machine.isThisMac {
                    Button(role: .destructive) { pendingRemoval = machine } label: {
                        Image(systemName: "trash")
                    }
                    .help("Remove \(machine.name)")
                    .accessibilityLabel("Remove \(machine.name)")
                }
            }
        } label: {
            Text(machine.name)
            Text(Self.summary(machine))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// One line: how the machine is reached, and whether Rex actions work on it.
    static func summary(_ machine: Machine) -> String {
        switch machine.kind {
        case .thisMac(let address):
            return "Directly at \(address)"
        case .remote(let remote):
            let port = remote.sshPort.map { " -p \($0)" } ?? ""
            let rex = remote.rexHost.map { "rex -S \($0)" } ?? "no Rex actions"
            let daemonPort = remote.daemonPort == RemoteMachine.defaultDaemonPort ? "" : " · daemon port \(remote.daemonPort)"
            return "ssh\(port) \(remote.destination)\(daemonPort) · \(rex)"
        }
    }

    private var removalShown: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private func save() {
        guard let current = form else { return }
        do throws(MachineValidationError) {
            switch current.target {
            case .thisMac: _ = try editing.saveThisMacAddress(current.address)
            case .add: _ = try editing.save(current.draft, nil)
            case .edit(let id): _ = try editing.save(current.draft, id)
            }
            form = nil
        } catch {
            form?.error = error.description
        }
    }

    private func remove(_ machine: Machine) {
        pendingRemoval = nil
        do throws(MachineValidationError) {
            try editing.remove(machine.id)
            removeError = nil
            if case .edit(machine.id) = form?.target { form = nil }
        } catch {
            removeError = error.description
        }
    }
}
