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

/// The Machines section: the list with Edit and Remove, Add Machine, and the form.
struct MachinesSection: View {
    let machines: [Machine]
    let editing: MachineEditing
    /// Why the list could not be stored, if it could not.
    let storeProblem: String?
    @Binding var form: MachineForm?
    @State private var pendingRemoval: Machine?
    @State private var removeError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Machines")
                .font(.rowLabel)
                .foregroundStyle(Theme.text)
            VStack(spacing: 0) {
                ForEach(Array(machines.enumerated()), id: \.element.id) { index, machine in
                    if index > 0 { Rectangle().fill(Theme.divider).frame(height: 1) }
                    row(machine)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
            if let form = Binding($form) {
                MachineFormView(form: form, onCancel: { self.form = nil }, onSave: save)
            } else {
                Button("Add Machine…") { form = MachineForm(target: .add) }
            }
            if let problem = removeError ?? storeProblem {
                Text(problem)
                    .font(.system(size: 11))
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
    }

    private func row(_ machine: Machine) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(machine.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(Self.summary(machine))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dimText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button("Edit") { form = .editing(machine) }
                .buttonStyle(ThemeButtonStyle(color: Theme.accent))
            if !machine.isThisMac {
                Button { pendingRemoval = machine } label: {
                    Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(ThemeButtonStyle(color: Theme.dimText))
                .help("Remove \(machine.name)")
                .accessibilityLabel("Remove \(machine.name)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
