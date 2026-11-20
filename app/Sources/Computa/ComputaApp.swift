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
            DashboardView(state: model.store.state, sample: model.store.sample, host: model.store.host)
                .background(WindowVisibilityReader { model.store.setOpen($0, .dashboard) })
        }
        .defaultLaunchBehavior(.suppressed)

        Window("Computa Preferences", id: WindowID.preferences) {
            PreferencesView(current: model.store.endpoint) { (text) throws(DaemonEndpointError) in
                try model.saveAddress(text)
            }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

enum WindowID {
    static let dashboard = "dashboard"
    static let preferences = "preferences"
}
