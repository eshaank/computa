import Foundation

/// A remote machine as typed in Preferences: every field is text, checked by `validate`.
public struct MachineDraft: Sendable, Equatable {
    public var name: String
    public var destination: String
    /// Empty: ssh's default.
    public var sshPort: String
    public var daemonPort: String
    /// Empty: no Rex actions on this machine.
    public var rexHost: String

    public init(
        name: String = "", destination: String = "", sshPort: String = "",
        daemonPort: String = String(RemoteMachine.defaultDaemonPort), rexHost: String = ""
    ) {
        self.name = name
        self.destination = destination
        self.sshPort = sshPort
        self.daemonPort = daemonPort
        self.rexHost = rexHost
    }

    /// The fields of a stored machine, for editing it.
    public init(_ name: String, _ remote: RemoteMachine) {
        self.init(
            name: name, destination: remote.destination, sshPort: remote.sshPort.map(String.init) ?? "",
            daemonPort: String(remote.daemonPort), rexHost: remote.rexHost ?? ""
        )
    }

    /// Checks every field.
    ///
    /// - Parameters:
    ///   - machines: The list the machine goes into, for the duplicate-name check.
    ///   - editing: The id of the machine being edited, whose own name does not count.
    /// - Returns: The trimmed name and the machine's settings.
    /// - Throws: The first problem found, in the order of the form's fields.
    public func validate(
        against machines: [Machine], editing: String? = nil
    ) throws(MachineValidationError) -> (name: String, remote: RemoteMachine) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .emptyName }
        let taken = machines.contains { $0.id != editing && $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard !taken else { throw .duplicateName(name) }
        let destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.checkDestination(destination)
        let sshPort = try Self.port(sshPort, field: "SSH port", optional: true)
        guard let daemonPort = try Self.port(daemonPort, field: "Daemon port", optional: false) else {
            throw .badPort(field: "Daemon port", text: "")
        }
        let rexHost = rexHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rexHost.isEmpty, !Self.isSafeArgument(rexHost) { throw .badRexHost(rexHost) }
        return (name, RemoteMachine(
            destination: destination, sshPort: sshPort, daemonPort: daemonPort, rexHost: rexHost.isEmpty ? nil : rexHost
        ))
    }

    /// A destination must never be read as an ssh option, so it cannot start with "-", and it
    /// is one argument, so it has no whitespace.
    ///
    /// - Throws: `.emptyDestination` or `.badDestination`.
    public static func checkDestination(_ destination: String) throws(MachineValidationError) {
        guard !destination.isEmpty else { throw .emptyDestination }
        guard isSafeArgument(destination), !destination.hasSuffix("@") else { throw .badDestination(destination) }
    }

    /// Not empty, no leading "-", and no whitespace or control characters.
    static func isSafeArgument(_ text: String) -> Bool {
        guard let first = text.first, first != "-" else { return false }
        return !text.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }
    }

    private static func port(_ text: String, field: String, optional: Bool) throws(MachineValidationError) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty, optional { return nil }
        guard let port = Int(trimmed), (1...65535).contains(port) else { throw .badPort(field: field, text: trimmed) }
        return port
    }
}

/// Why a machine could not be saved, removed or used, each as one sentence for Preferences.
public enum MachineValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyName
    case duplicateName(String)
    case emptyDestination
    case badDestination(String)
    case badPort(field: String, text: String)
    case badRexHost(String)
    case badAddress(DaemonEndpointError)
    case cannotRemoveThisMac
    /// This Mac has only an address, set with `MachineList.setThisMacAddress`.
    case thisMacIsNotRemote
    case unknownMachine(String)

    public var description: String {
        switch self {
        case .emptyName:
            "Give the machine a name."
        case .duplicateName(let name):
            "There is already a machine called \u{201C}\(name)\u{201D}."
        case .emptyDestination:
            "Enter the SSH destination, as you would type it after ssh, for example morgan@100.64.0.5."
        case .badDestination(let text):
            "\u{201C}\(text)\u{201D} is not an SSH destination. Use user@host, with no spaces and not starting with \u{201C}-\u{201D}."
        case .badPort(let field, let text):
            text.isEmpty
                ? "\(field) is missing; enter a number between 1 and 65535."
                : "\(field) \u{201C}\(text)\u{201D} is not a number between 1 and 65535."
        case .badRexHost(let text):
            "Rex host label \u{201C}\(text)\u{201D} cannot start with \u{201C}-\u{201D} or contain spaces."
        case .badAddress(let error):
            "This Mac's daemon address: \(error.description)."
        case .cannotRemoveThisMac:
            "This Mac cannot be removed."
        case .thisMacIsNotRemote:
            "This Mac is reached directly; only its daemon address can be changed."
        case .unknownMachine(let id):
            "No machine with id \(id); it may have been removed."
        }
    }
}
