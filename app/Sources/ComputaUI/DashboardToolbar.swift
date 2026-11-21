import ComputaCore
import SwiftUI

/// The dashboard's toolbar, as in Activity Monitor: the tabs as a segmented control in the
/// middle, and with more than one machine a menu to switch machines at the leading edge.
struct DashboardToolbar: ToolbarContent {
    @Binding var tab: DashboardTab
    let machine: MachineContext
    let switching: MachineSwitching

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if machine.showsSwitcher {
                MachinePicker(machine: machine, switching: switching)
            }
        }
        ToolbarItem(placement: .principal) {
            DashboardTabPicker(tab: $tab)
        }
    }
}

/// The tabs as a native segmented control.
public struct DashboardTabPicker: View {
    @Binding var tab: DashboardTab

    public init(tab: Binding<DashboardTab>) {
        _tab = tab
    }

    public var body: some View {
        Picker("View", selection: $tab) {
            ForEach(DashboardTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Choose what the dashboard shows")
    }
}

/// The machine shown, as a toolbar menu of the machines.
public struct MachinePicker: View {
    let machine: MachineContext
    let switching: MachineSwitching

    public init(machine: MachineContext, switching: MachineSwitching) {
        self.machine = machine
        self.switching = switching
    }

    public var body: some View {
        MachineMenu(machine: machine, switching: switching) {
            Label(machine.name, systemImage: machine.isRemote ? "network" : "laptopcomputer")
                .labelStyle(.titleAndIcon)
        }
        .fixedSize()
        .help("Choose the machine to watch")
    }
}

/// The 5m / 15m / 1h choice as a native segmented control.
struct RangePicker: View {
    @Binding var range: HistoryRange

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(HistoryRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help("How far back the chart reaches")
    }
}

/// Above the chart: the tab's name and live headline, and the range on the right.
struct ChartHeader: View {
    let tab: DashboardTab
    let sample: SystemSample?
    @Binding var range: HistoryRange

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(tab.chartTitle)
                .font(.headline)
            Spacer(minLength: 8)
            RangePicker(range: $range)
        }
    }
}

extension DashboardTab {
    /// The heading above the tab's chart.
    var chartTitle: String {
        switch self {
        case .cpu: "CPU Load"
        case .memory: "Memory Used"
        case .network: "Network"
        case .disk: "Disk Activity"
        case .sessions: "Sessions"
        }
    }
}
