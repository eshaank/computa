import Foundation

/// The machines the app knows, This Mac first, and which one is shown.
public struct MachineList: Sendable, Equatable {
    public private(set) var machines: [Machine]
    public private(set) var selectedID: String

    /// A list with This Mac at `address`, selected.
    public init(thisMacAddress address: DaemonEndpoint = .local) {
        machines = [.thisMac(address: address)]
        selectedID = Machine.thisMacID
    }

    /// Restores a stored list. This Mac is put first, added if missing; a selection that names
    /// no machine selects This Mac.
    public init(machines stored: [Machine], selectedID: String?) {
        var machines = stored.filter { !$0.isThisMac }
        let thisMac = stored.first { $0.isThisMac } ?? .thisMac()
        machines.insert(Machine(id: Machine.thisMacID, name: Machine.thisMacName, kind: thisMac.kind), at: 0)
        self.machines = machines
        self.selectedID = selectedID.flatMap { id in machines.contains { $0.id == id } ? id : nil } ?? Machine.thisMacID
    }

    public var selected: Machine {
        machines.first { $0.id == selectedID } ?? machines[0]
    }

    public var thisMacAddress: DaemonEndpoint {
        if case .thisMac(let address) = machines[0].kind { address } else { .local }
    }

    public func machine(_ id: String) -> Machine? {
        machines.first { $0.id == id }
    }

    /// - Throws: `.unknownMachine` when no machine has the id; the selection is kept.
    public mutating func select(_ id: String) throws(MachineValidationError) {
        guard machine(id) != nil else { throw .unknownMachine(id) }
        selectedID = id
    }

    /// Adds a remote machine.
    ///
    /// - Returns: The new machine, with a fresh id.
    /// - Throws: The draft's first problem; nothing is added then.
    @discardableResult
    public mutating func add(_ draft: MachineDraft, id: String = UUID().uuidString) throws(MachineValidationError) -> Machine {
        let (name, remote) = try draft.validate(against: machines)
        let machine = Machine(id: id, name: name, kind: .remote(remote))
        machines.append(machine)
        return machine
    }

    /// Replaces a remote machine's settings; its id stays.
    ///
    /// - Throws: `.unknownMachine`, `.thisMacIsNotRemote` for This Mac (edit its address with
    ///   `setThisMacAddress`), or the draft's first problem.
    @discardableResult
    public mutating func update(_ id: String, with draft: MachineDraft) throws(MachineValidationError) -> Machine {
        guard let index = machines.firstIndex(where: { $0.id == id }) else { throw .unknownMachine(id) }
        guard !machines[index].isThisMac else { throw .thisMacIsNotRemote }
        let (name, remote) = try draft.validate(against: machines, editing: id)
        machines[index] = Machine(id: id, name: name, kind: .remote(remote))
        return machines[index]
    }

    /// Checks and stores This Mac's daemon address, `host:port`.
    @discardableResult
    public mutating func setThisMacAddress(_ text: String) throws(MachineValidationError) -> DaemonEndpoint {
        let address: DaemonEndpoint
        do {
            address = try DaemonEndpoint(parsing: text.trimmingCharacters(in: .whitespaces))
        } catch {
            throw .badAddress(error)
        }
        machines[0] = .thisMac(address: address)
        return address
    }

    /// Removes a remote machine. Removing the selected one selects This Mac.
    ///
    /// - Throws: `.cannotRemoveThisMac` or `.unknownMachine`.
    public mutating func remove(_ id: String) throws(MachineValidationError) {
        guard id != Machine.thisMacID else { throw .cannotRemoveThisMac }
        guard let index = machines.firstIndex(where: { $0.id == id }) else { throw .unknownMachine(id) }
        machines.remove(at: index)
        if selectedID == id { selectedID = Machine.thisMacID }
    }
}
