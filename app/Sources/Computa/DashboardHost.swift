import AppKit
import ComputaCore
import ComputaUI
import SwiftUI

/// Connects the dashboard view to the app model: owns the tab, range, search text, expanded
/// groups and the Sessions tab's sort and open rows, and tells the stores when the window opens
/// or closes and which tab shows.
struct DashboardHost: View {
    let model: AppModel
    @State private var tab: DashboardTab = .cpu
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var sessionsView = SessionsViewState()
    @State private var icons = LocalAppIconProvider()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        DashboardView(
            content: model.dashboardContent,
            tab: $tab,
            range: Binding(get: { model.history.range }, set: { model.history.setRange($0) }),
            query: $query,
            expanded: $expanded,
            sessionsView: $sessionsView,
            icons: model.iconProvider(local: icons),
            sessionActions: model.sessionActions,
            machines: machineSwitching
        )
        .background(WindowVisibilityReader { model.setDashboardOpen($0) })
        .onDisappear { model.setDashboardOpen(false) }
        .onChange(of: tab, initial: true) { _, newTab in model.setDashboardTab(newTab) }
        // Open rows belong to the machine they were opened on.
        .onChange(of: model.machines.selected.id) {
            expanded = []
            sessionsView.expanded = []
        }
    }

    private var machineSwitching: MachineSwitching {
        let model = model
        let openWindow = openWindow
        return MachineSwitching(
            select: { model.machines.select($0) },
            manage: {
                openWindow(id: WindowID.preferences)
                NSApplication.shared.activate()
            }
        )
    }
}
