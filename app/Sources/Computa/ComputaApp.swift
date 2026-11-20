import AppKit
import ComputaCore
import ComputaUI
import SwiftUI

@main
struct ComputaApp: App {
    @State private var model: AppModel

    init() {
        // A menu bar app: no Dock icon, no app menu.
        NSApplication.shared.setActivationPolicy(.accessory)
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverHost(model: model)
        } label: {
            MenuBarLabel(cpuPercent: model.store.sample?.cpu.usagePercent)
        }
        .menuBarExtraStyle(.window)

        Window("Computa Dashboard", id: WindowID.dashboard) {
            DashboardHost(model: model)
        }
        .defaultSize(width: 460, height: 760)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Computa Preferences", id: WindowID.preferences) {
            PreferencesView(
                machines: model.machines.list.machines,
                editing: model.machineEditing,
                storeProblem: model.machines.saveProblem,
                rexCommand: model.rexSetting.path,
                rexLookup: model.rexSetting.lookup(),
                saveRexCommand: { model.saveRexCommand($0) }
            )
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

enum WindowID {
    static let dashboard = "dashboard"
    static let preferences = "preferences"
}
