import Foundation
import os

/// The machine list and the selected machine, kept in `UserDefaults` as JSON.
///
/// Before phase 6 the app stored one daemon address under `DaemonAddressSetting.key`. The
/// first load moves it into This Mac, so nobody loses a custom address.
public struct MachineSettings {
    public static let machinesKey = "machines"
    public static let selectedKey = "selectedMachine"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "app.computa.Computa", category: "settings")

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The stored list; when none is stored, This Mac at the old single address. A stored list
    /// that cannot be read is logged and replaced the same way, so the app always starts.
    public func load() -> MachineList {
        let selected = defaults.string(forKey: Self.selectedKey)
        guard let data = defaults.data(forKey: Self.machinesKey) else {
            let address = DaemonAddressSetting(defaults: defaults).endpoint
            logger.info("no machine list stored; This Mac at \(address, privacy: .public)")
            return MachineList(thisMacAddress: address)
        }
        do {
            let machines = try JSONDecoder().decode([Machine].self, from: data)
            return MachineList(machines: machines, selectedID: selected)
        } catch {
            logger.error("stored machine list cannot be read, starting from This Mac: \(error, privacy: .public)")
            return MachineList(thisMacAddress: DaemonAddressSetting(defaults: defaults).endpoint)
        }
    }

    /// Stores the list and the selection.
    ///
    /// - Throws: The encoding error, after logging it; nothing is stored then.
    public func save(_ list: MachineList) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(list.machines)
        } catch {
            logger.error("could not encode the machine list: \(error, privacy: .public)")
            throw error
        }
        defaults.set(data, forKey: Self.machinesKey)
        defaults.set(list.selectedID, forKey: Self.selectedKey)
    }
}
