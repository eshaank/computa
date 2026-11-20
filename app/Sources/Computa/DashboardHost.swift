import ComputaCore
import ComputaUI
import SwiftUI

/// Connects the dashboard view to the app model: owns the tab, range, search text and expanded
/// groups, and tells the stores when the window opens or closes and which tab shows.
struct DashboardHost: View {
    let model: AppModel
    @State private var tab: DashboardTab = .cpu
    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var icons = LocalAppIconProvider()

    var body: some View {
        DashboardView(
            content: model.dashboardContent,
            tab: $tab,
            range: Binding(get: { model.history.range }, set: { model.history.setRange($0) }),
            query: $query,
            expanded: $expanded,
            icons: icons
        )
        .background(WindowVisibilityReader { model.setDashboardOpen($0) })
        .onDisappear { model.setDashboardOpen(false) }
        .onChange(of: tab, initial: true) { _, newTab in model.processes.setTab(newTab) }
    }
}
