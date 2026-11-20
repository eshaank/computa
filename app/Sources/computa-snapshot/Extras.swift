import AppKit
import ComputaCore
import ComputaUI
import SwiftUI

/// The views outside the popover.
@MainActor
func renderExtras() throws {
    try render(
        DashboardView(state: .connected, sample: Fixtures.sample, host: Fixtures.host).frame(width: 440),
        named: "dashboard-placeholder"
    )
    // ImageRenderer draws AppKit-backed controls such as TextField as placeholders, so this
    // view goes through an NSHostingView instead.
    try renderHosted(
        PreferencesView(current: .local) { (text) throws(DaemonEndpointError) in try DaemonEndpoint(parsing: text) },
        named: "preferences"
    )
    try render(
        HStack(spacing: 24) {
            MenuBarLabel(cpuPercent: Fixtures.sample.cpu.usagePercent)
            MenuBarLabel(cpuPercent: nil)
        }
        .foregroundStyle(.white)
        .font(.system(size: 13)),
        named: "menu-bar-labels"
    )
}

/// Renders through an offscreen `NSHostingView`, which draws real AppKit controls.
@MainActor
func renderHosted(_ view: some View, named name: String) throws {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: Backdrop(content: view))
    host.appearance = NSAppearance(named: .darkAqua)
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        throw SnapshotError(description: "NSHostingView gave no bitmap for \(name)")
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw SnapshotError(description: "could not encode \(name) as PNG")
    }
    let file = outputDirectory.appendingPathComponent("\(name).png")
    try data.write(to: file)
    print("\(file.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}
