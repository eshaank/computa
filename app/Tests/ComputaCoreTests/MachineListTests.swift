import Foundation
import Testing

@testable import ComputaCore

@Suite struct MachineListTests {
    func freshDefaults() -> UserDefaults {
        let name = "computa-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    let m1 = MachineDraft(name: "M1", destination: "eshaan@100.64.0.5", rexHost: "m1")

    @Test func migratesTheOldSingleAddressIntoThisMac() {
        let defaults = freshDefaults()
        defaults.set("127.0.0.1:7401", forKey: DaemonAddressSetting.key)
        let list = MachineSettings(defaults: defaults).load()
        #expect(list.machines.count == 1)
        #expect(list.selected.isThisMac)
        #expect(list.selected.kind == .thisMac(address: DaemonEndpoint(host: "127.0.0.1", port: 7401)))
    }

    @Test func startsWithThisMacOnTheDefaultAddress() {
        let list = MachineSettings(defaults: freshDefaults()).load()
        #expect(list.machines == [.thisMac()])
        #expect(list.thisMacAddress == .local)
    }

    @Test func persistenceRoundTripKeepsMachinesAndSelection() throws {
        let defaults = freshDefaults()
        var list = MachineList()
        let added = try list.add(MachineDraft(name: "M1", destination: "me@m1", sshPort: "2222", daemonPort: "7400", rexHost: "m1"))
        try list.add(MachineDraft(name: "Studio", destination: "studio.local"))
        try list.setThisMacAddress("127.0.0.1:7301")
        try list.select(added.id)
        try MachineSettings(defaults: defaults).save(list)

        let loaded = MachineSettings(defaults: defaults).load()
        #expect(loaded == list)
        #expect(loaded.selected.remote == RemoteMachine(destination: "me@m1", sshPort: 2222, daemonPort: 7400, rexHost: "m1"))
        #expect(loaded.machines[2].remote?.rexHost == nil)
        // The stored list wins over the old single address from now on.
        defaults.set("10.0.0.1:9999", forKey: DaemonAddressSetting.key)
        #expect(MachineSettings(defaults: defaults).load().thisMacAddress.port == 7301)
    }

    @Test func unreadableStoredListFallsBackToThisMac() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: MachineSettings.machinesKey)
        #expect(MachineSettings(defaults: defaults).load().machines == [.thisMac()])
    }

    @Test func addEditAndRemove() throws {
        var list = MachineList()
        let added = try list.add(m1)
        #expect(list.machines.map(\.name) == ["This Mac", "M1"])
        #expect(added.remote?.daemonPort == 7300)
        #expect(added.remote?.sshPort == nil)

        var edited = m1
        edited.name = " M1 mini "
        edited.sshPort = "22"
        edited.rexHost = ""
        let updated = try list.update(added.id, with: edited)
        #expect(updated.id == added.id)
        #expect(updated.name == "M1 mini")
        #expect(updated.remote == RemoteMachine(destination: "eshaan@100.64.0.5", sshPort: 22, rexHost: nil))

        try list.remove(added.id)
        #expect(list.machines.map(\.id) == [Machine.thisMacID])
        #expect(throws: MachineValidationError.unknownMachine(added.id)) { try list.remove(added.id) }
    }

    @Test func thisMacCannotBeRemovedOrEditedAsRemote() throws {
        var list = MachineList()
        #expect(throws: MachineValidationError.cannotRemoveThisMac) { try list.remove(Machine.thisMacID) }
        #expect(throws: MachineValidationError.thisMacIsNotRemote) { try list.update(Machine.thisMacID, with: m1) }
        #expect(list.machines.count == 1)
        #expect(throws: MachineValidationError.badAddress(.missingPort("nonsense"))) { try list.setThisMacAddress("nonsense") }
        #expect(try list.setThisMacAddress(" 127.0.0.1:7302 ") == DaemonEndpoint(host: "127.0.0.1", port: 7302))
    }

    @Test func removingTheSelectedMachineSelectsThisMac() throws {
        var list = MachineList()
        let added = try list.add(m1)
        try list.select(added.id)
        #expect(list.selected.id == added.id)
        try list.remove(added.id)
        #expect(list.selected.isThisMac)
    }

    @Test func aStoredSelectionOfAMissingMachineSelectsThisMac() {
        let list = MachineList(machines: [.thisMac()], selectedID: "gone")
        #expect(list.selected.isThisMac)
    }

    @Test(arguments: [
        (MachineDraft(name: "  ", destination: "me@m1"), MachineValidationError.emptyName),
        (MachineDraft(name: "this mac", destination: "me@m1"), .duplicateName("this mac")),
        (MachineDraft(name: "N", destination: " "), .emptyDestination),
        (MachineDraft(name: "N", destination: "-oProxyCommand=evil"), .badDestination("-oProxyCommand=evil")),
        (MachineDraft(name: "N", destination: "me@m1 -p 1"), .badDestination("me@m1 -p 1")),
        (MachineDraft(name: "N", destination: "me@m\t1"), .badDestination("me@m\t1")),
        (MachineDraft(name: "N", destination: "me@"), .badDestination("me@")),
        (MachineDraft(name: "N", destination: "me@m1", sshPort: "0"), .badPort(field: "SSH port", text: "0")),
        (MachineDraft(name: "N", destination: "me@m1", sshPort: "ssh"), .badPort(field: "SSH port", text: "ssh")),
        (MachineDraft(name: "N", destination: "me@m1", daemonPort: "70000"), .badPort(field: "Daemon port", text: "70000")),
        (MachineDraft(name: "N", destination: "me@m1", daemonPort: ""), .badPort(field: "Daemon port", text: "")),
        (MachineDraft(name: "N", destination: "me@m1", rexHost: "-x"), .badRexHost("-x")),
        (MachineDraft(name: "N", destination: "me@m1", rexHost: "m 1"), .badRexHost("m 1")),
    ])
    func validationRejects(_ draft: MachineDraft, _ expected: MachineValidationError) {
        var list = MachineList()
        #expect(throws: expected) { try list.add(draft) }
        #expect(list.machines.count == 1, "nothing is added")
        #expect(!expected.description.isEmpty)
    }

    @Test func duplicateNamesAreCaseInsensitiveButAMachineKeepsItsOwnName() throws {
        var list = MachineList()
        let added = try list.add(m1)
        #expect(throws: MachineValidationError.duplicateName("m1")) {
            try list.add(MachineDraft(name: "m1", destination: "other@host"))
        }
        var renamed = m1
        renamed.destination = "eshaan@m1.netbird"
        #expect(try list.update(added.id, with: renamed).remote?.destination == "eshaan@m1.netbird")
    }

    @Test func messagesSayWhatToDo() {
        #expect(MachineValidationError.badDestination("-oX").description.contains("not starting with"))
        #expect(MachineValidationError.badPort(field: "SSH port", text: "0").description == "SSH port \u{201C}0\u{201D} is not a number between 1 and 65535.")
    }
}
