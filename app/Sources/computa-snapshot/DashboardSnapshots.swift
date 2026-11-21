import AppKit
import ComputaCore
import ComputaUI
import SwiftUI

/// The dashboard on every tab and in each state. The dashboard holds a scroll view and a real
/// text field, which `ImageRenderer` does not draw, so these go through an `NSHostingView`.
@MainActor
func renderDashboards() throws {
    let icons = LocalAppIconProvider()
    let unreachable = DaemonProblem(
        kind: .unreachable, summary: "computad is not running at 127.0.0.1:7300.", detail: "unavailable"
    )
    let unsupported = DaemonProblem(
        kind: .unsupported, summary: "computad at 127.0.0.1:7300 does not offer this call yet. Update the daemon.",
        detail: "unimplemented"
    )
    func shot(
        _ name: String, _ tab: DashboardTab, content: DashboardContent = dashboardContent(), query: String = "",
        expanded: Set<String> = [], height: CGFloat = 760
    ) throws {
        let view = DashboardView(
            content: content, tab: .constant(tab), range: .constant(.fifteenMinutes), query: .constant(query),
            expanded: .constant(expanded), icons: icons
        )
        try renderWindow(view, size: CGSize(width: 460, height: height), named: name)
    }
    try shot("dashboard-cpu", .cpu, expanded: ["pid:8812"])
    try shot("dashboard-mem", .memory, expanded: ["/Applications/Spotify.app"])
    try shot("dashboard-mem-full", .memory, expanded: ["/Applications/Spotify.app"], height: 1060)
    try shot("dashboard-net", .network)
    try shot("dashboard-disk", .disk)
    try shot("dashboard-search", .memory, query: "helper", expanded: ["/Applications/1Password.app"])
    try shot("dashboard-connecting", .cpu, content: dashboardContent(state: .connecting))
    try shot("dashboard-daemon-not-running", .cpu, content: dashboardContent(state: .daemonNotRunning(unreachable)))
    try shot(
        "dashboard-loading", .cpu,
        content: dashboardContent(history: nil, processState: .connecting)
    )
    try shot(
        "dashboard-processes-need-update", .memory,
        content: dashboardContent(processState: .daemonNotRunning(unsupported))
    )
    try shot(
        "dashboard-history-need-update", .network,
        content: dashboardContent(history: nil, historyProblem: unsupported)
    )
    try renderWindow(
        DashboardView(
            content: dashboardContent(), tab: .constant(.cpu), range: .constant(.oneHour), query: .constant(""),
            expanded: .constant(["/Applications/Google Chrome.app"]), icons: icons
        ),
        size: CGSize(width: 720, height: 760), named: "dashboard-wide"
    )
}

@MainActor
func dashboardContent(
    state: ConnectionState = .connected, history: HistorySeries? = Fixtures.history(),
    historyProblem: DaemonProblem? = nil, processState: ConnectionState = .connected
) -> DashboardContent {
    DashboardContent(
        state: state, sample: Fixtures.dashboardSample, host: Fixtures.host, endpoint: .local,
        history: history, historyProblem: historyProblem,
        processState: processState, processes: Fixtures.processes
    )
}

/// Renders a window-sized view through an offscreen `NSHostingView` at the screen's scale, and
/// converts the result to sRGB so the colours in the PNG are the theme's.
@MainActor
func renderWindow(_ view: some View, size: CGSize, named name: String) throws {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.appearance = NSAppearance(named: .darkAqua)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        throw SnapshotError(description: "NSHostingView gave no bitmap for \(name)")
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let srgb = rep.converting(to: .sRGB, renderingIntent: .default),
          let data = srgb.representation(using: .png, properties: [:])
    else {
        throw SnapshotError(description: "could not encode \(name) as sRGB PNG")
    }
    let file = outputDirectory.appendingPathComponent("\(name).png")
    try data.write(to: file)
    print("\(file.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}
