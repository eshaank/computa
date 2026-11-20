import AppKit
import ComputaCore
import ComputaUI
import SwiftUI

/// The views outside the popover.
@MainActor
func renderExtras() throws {
    try renderDashboards()
    // ImageRenderer draws AppKit-backed controls such as TextField as placeholders, so this
    // view goes through an NSHostingView instead.
    let installed = "/Users/eshaan/" + RexLocator.installPath
    try renderHosted(preferences(rexCommand: "", lookup: .found(path: installed, source: .installLocation)), named: "preferences")
    try renderHosted(preferences(rexCommand: "", lookup: .notFound), named: "preferences-rex-not-found")
    try renderHosted(
        preferences(rexCommand: "/opt/rex/rex", lookup: .settingInvalid(path: "/opt/rex/rex")),
        named: "preferences-rex-invalid"
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

@MainActor
private func preferences(rexCommand: String, lookup: RexLookup) -> PreferencesView {
    PreferencesView(
        current: .local, save: { (text) throws(DaemonEndpointError) in try DaemonEndpoint(parsing: text) },
        rexCommand: rexCommand, rexLookup: lookup, saveRexCommand: { _ in lookup }
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
