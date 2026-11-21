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
        expanded: Set<String> = [], height: CGFloat = 760, width: CGFloat = dashboardWidth
    ) throws {
        let view = DashboardView(
            content: content, tab: .constant(tab), range: .constant(.fifteenMinutes), query: .constant(query),
            expanded: .constant(expanded), sessionsView: .constant(SessionsViewState()), icons: icons
        )
        try renderWindow(view, size: CGSize(width: width, height: height), named: name)
    }
    try shot("dashboard-cpu", .cpu, expanded: ["pid:8812"])
    try shot("dashboard-mem", .memory, expanded: ["/Applications/Spotify.app"])
    try shot("dashboard-mem-full", .memory, expanded: ["/Applications/Spotify.app"], height: 1060)
    try shot(
        "dashboard-mem-minimum-width", .memory, expanded: ["/Applications/Spotify.app"],
        height: minimumDashboardSize.height, width: minimumDashboardSize.width
    )
    try shot("dashboard-net", .network, expanded: ["/Applications/Spotify.app"])
    try renderTrafficStates { name, content in try shot(name, .network, content: content) }
    try shot(
        "dashboard-mem-old-daemon", .memory,
        content: dashboardContent(processes: withoutResidentSizes(Fixtures.processes)), height: 700
    )
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
    try shot("dashboard-wide", .cpu, expanded: ["/Applications/Google Chrome.app"], width: 960)
    try renderSessionTabs(icons: icons)
}

@MainActor
func dashboardContent(
    state: ConnectionState = .connected, history: HistorySeries? = Fixtures.history(),
    historyProblem: DaemonProblem? = nil, processState: ConnectionState = .connected,
    sessionsState: ConnectionState = .connected, sessions: SessionsSnapshot = Fixtures.sessions,
    processes: ProcessSnapshot = Fixtures.processes, sample: SystemSample = Fixtures.dashboardSample
) -> DashboardContent {
    DashboardContent(
        state: state, sample: sample, host: Fixtures.host, endpoint: .local,
        history: history, historyProblem: historyProblem,
        processState: processState, processes: processes,
        sessionsState: sessionsState, sessions: sessions
    )
}

/// The dashboard's default width.
let dashboardWidth: CGFloat = 760

/// The dashboard window's minimum width (`DashboardMetrics.minimumSize` in ComputaUI).
let minimumDashboardSize = CGSize(width: 700, height: 700)

/// The Net tab's app list before its first rates, with a daemon problem, and from a daemon
/// too old to measure traffic.
@MainActor
private func renderTrafficStates(_ shot: (String, DashboardContent) throws -> Void) throws {
    func with(_ network: ProcessNetworkStatus?) -> DashboardContent {
        var processes = Fixtures.processes
        processes.network = network
        return dashboardContent(processes: processes)
    }
    try shot("dashboard-net-measuring", with(ProcessNetworkStatus(available: false)))
    try shot("dashboard-net-problem", with(ProcessNetworkStatus(available: false, problem: "nettop failed: exit status 1")))
    try shot("dashboard-net-needs-update", with(nil))
}

/// A snapshot as a daemon older than resident sizes sends it: every resident size 0.
func withoutResidentSizes(_ snapshot: ProcessSnapshot) -> ProcessSnapshot {
    var snapshot = snapshot
    for g in snapshot.groups.indices {
        for p in snapshot.groups[g].processes.indices { snapshot.groups[g].processes[p].residentBytes = 0 }
    }
    return snapshot
}

/// Renders a window-sized view in a real, never-shown `NSWindow`, so its toolbar and title are
/// drawn too, at the screen's scale, and converts the result to sRGB so the colours in the PNG
/// are the theme's. The image is the whole window frame, title bar included.
@MainActor
func renderWindow(_ view: some View, size: CGSize, named name: String) throws {
    _ = NSApplication.shared
    let controller = NSHostingController(rootView: view.frame(width: size.width, height: size.height))
    controller.sceneBridgingOptions = [.toolbars, .title]
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.appearance = NSAppearance(named: .darkAqua)
    window.toolbarStyle = .unified
    window.contentViewController = controller
    window.setContentSize(size)
    // Lets SwiftUI install the toolbar and title, which it does on a later turn of the run loop.
    // The toolbar draws, but its selected segment comes out as a blank white pill offscreen;
    // `dashboard-tab-picker.png` shows the same control hosted on its own.
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    guard let frame = window.contentView?.superview else {
        throw SnapshotError(description: "the window for \(name) has no frame view")
    }
    frame.layoutSubtreeIfNeeded()
    try writePNG(of: frame, named: name)
}

/// Draws `view` into a bitmap and writes it as an sRGB PNG in the output directory.
@MainActor
func writePNG(of view: NSView, named name: String) throws {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw SnapshotError(description: "no bitmap for \(name)")
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let srgb = rep.converting(to: .sRGB, renderingIntent: .default),
          let data = srgb.representation(using: .png, properties: [:])
    else {
        throw SnapshotError(description: "could not encode \(name) as sRGB PNG")
    }
    let file = outputDirectory.appendingPathComponent("\(name).png")
    try data.write(to: file)
    print("\(file.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}
