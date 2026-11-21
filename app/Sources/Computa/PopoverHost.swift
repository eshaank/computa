import AppKit
import ComputaCore
import ComputaUI
import SwiftUI

/// Connects the popover view to the app model and the window actions.
struct PopoverHost: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    /// How long a Prevent Sleep failure stays on screen.
    private static let errorDisplayTime: Duration = .seconds(6)

    var body: some View {
        PopoverView(content: model.popoverContent, actions: actions)
            .padding(.bottom, 2)
            .background(ClearWindowBackground())
            .background(WindowVisibilityReader { model.setPopoverOpen($0) })
            .onDisappear { model.setPopoverOpen(false) }
            .task(id: model.sleep.lastError) { await clearSleepErrorLater() }
    }

    private var actions: PopoverActions {
        let model = model
        let openWindow = openWindow
        return PopoverActions(
            setPreventSleep: { model.sleep.set(on: $0) },
            openDashboard: { show(WindowID.dashboard, with: openWindow) },
            openPreferences: { show(WindowID.preferences, with: openWindow) },
            quit: { NSApplication.shared.terminate(nil) },
            machines: MachineSwitching(
                select: { model.machines.select($0) },
                manage: { show(WindowID.preferences, with: openWindow) }
            )
        )
    }

    private func clearSleepErrorLater() async {
        guard model.sleep.lastError != nil else { return }
        do {
            try await pause(for: Self.errorDisplayTime)
        } catch {
            return  // A newer error replaced this one, or the popover closed.
        }
        model.sleep.clearError()
    }
}

/// Opens a window and brings it forward; an accessory app is not active by itself.
@MainActor
private func show(_ id: String, with openWindow: OpenWindowAction) {
    openWindow(id: id)
    NSApplication.shared.activate()
}
