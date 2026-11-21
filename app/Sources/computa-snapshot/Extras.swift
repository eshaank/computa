import AppKit
import ComputaCore
import ComputaUI
import SwiftUI

/// The views outside the popover.
@MainActor
func renderExtras() throws {
    try renderDashboards()
    try renderMachines()
    // ImageRenderer draws AppKit-backed controls such as TextField as placeholders, so this
    // view goes through an NSHostingView instead.
    let installed = "/Users/morgan/" + RexLocator.installPath
    try renderHosted(
        preferences(rexCommand: "", lookup: .found(path: installed, source: .installLocation)), height: preferencesHeight,
        named: "preferences"
    )
    try renderHosted(preferences(rexCommand: "", lookup: .notFound), height: preferencesHeight, named: "preferences-rex-not-found")
    try renderHosted(
        preferences(rexCommand: "/opt/rex/rex", lookup: .settingInvalid(path: "/opt/rex/rex")), height: preferencesHeight,
        named: "preferences-rex-invalid"
    )
    try renderHosted(DashboardTabPicker(tab: .constant(.memory)).padding(8).background(Theme.background), named: "dashboard-tab-picker")
    try renderHosted(MemoryFiguresExplanation().background(Theme.background), named: "memory-figures-explanation")
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

/// Tall enough for Preferences with the add/edit form open.
let preferencesHeight: CGFloat = 780

@MainActor
func preferences(
    rexCommand: String, lookup: RexLookup, machines: [Machine] = [.thisMac()], form: MachineForm? = nil
) -> PreferencesView {
    PreferencesView(
        machines: machines, editing: previewEditing,
        rexCommand: rexCommand, rexLookup: lookup, saveRexCommand: { _ in lookup }, form: form
    )
}

/// Checks like the app does, against an empty list, and stores nothing.
@MainActor
let previewEditing = MachineEditing(
    save: { (draft, _) throws(MachineValidationError) in
        var list = MachineList()
        return try list.add(draft)
    },
    saveThisMacAddress: { (text) throws(MachineValidationError) in
        var list = MachineList()
        return try list.setThisMacAddress(text)
    },
    remove: { _ throws(MachineValidationError) in }
)

/// Renders through an offscreen `NSHostingView`, which draws real AppKit controls such as
/// switches and text fields, unlike `ImageRenderer`. `height` fixes the height of views that
/// scroll, such as a grouped form, whose fitting height is otherwise tiny.
@MainActor
func renderHosted(_ view: some View, height: CGFloat? = nil, named name: String) throws {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: Backdrop(content: view.frame(height: height)))
    host.appearance = NSAppearance(named: .darkAqua)
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    // Lets controls that finish drawing on a later turn of the run loop do so.
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    try writePNG(of: host, named: name)
}
