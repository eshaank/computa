import ComputaCore
import SwiftUI

/// The add/edit form's contents: which machine, the typed fields, and the last error.
public struct MachineForm: Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        case add
        case edit(id: String)
        /// This Mac: only its daemon address.
        case thisMac
    }

    public var target: Target
    public var draft: MachineDraft
    /// This Mac's address, `host:port`.
    public var address: String
    /// Why the last save failed.
    public var error: String?

    public init(target: Target, draft: MachineDraft = MachineDraft(), address: String = "", error: String? = nil) {
        self.target = target
        self.draft = draft
        self.address = address
        self.error = error
    }

    /// The form for a stored machine.
    public static func editing(_ machine: Machine) -> MachineForm {
        switch machine.kind {
        case .thisMac(let address): MachineForm(target: .thisMac, address: address.description)
        case .remote(let remote): MachineForm(target: .edit(id: machine.id), draft: MachineDraft(machine.name, remote))
        }
    }

    var title: String {
        switch target {
        case .add: "Add a machine"
        case .edit: "Edit \(draft.name)"
        case .thisMac: "This Mac"
        }
    }
}

/// The fields of the add/edit form, with Cancel and Save.
struct MachineFormView: View {
    @Binding var form: MachineForm
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(form.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
            if form.target == .thisMac {
                field("Daemon address", text: $form.address, prompt: DaemonEndpoint.local.description)
            } else {
                remoteFields
            }
            Text(form.error ?? hint)
                .font(.system(size: 11))
                .foregroundStyle(form.error == nil ? Theme.dimText : Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
    }

    @ViewBuilder
    private var remoteFields: some View {
        field("Name", text: $form.draft.name, prompt: "M1")
        field("SSH destination", text: $form.draft.destination, prompt: "eshaan@100.64.0.5")
        HStack(spacing: 10) {
            field("SSH port", text: $form.draft.sshPort, prompt: "22")
            field("Daemon port", text: $form.draft.daemonPort, prompt: String(RemoteMachine.defaultDaemonPort))
        }
        field("Rex host label (optional)", text: $form.draft.rexHost, prompt: "m1")
    }

    private var hint: String {
        switch form.target {
        case .thisMac:
            "host:port of the daemon on this Mac. The default is \(DaemonEndpoint.local)."
        case .add, .edit:
            "As you would type after ssh. Computa logs in with your SSH key; it cannot type a password. "
                + "The Rex host label is what you pass to rex\u{00A0}\u{2011}S, for the Sessions tab's actions."
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13).monospaced())
                .onSubmit(onSave)
        }
    }
}
