import AppKit
import SwiftUI

/// Reports whether the window holding this view is on screen, by watching the window's
/// occlusion state. Used to tell when the popover or the dashboard is open.
public struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    public init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
    }

    public func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }

    public func updateNSView(_ nsView: VisibilityView, context: Context) {
        nsView.onChange = onChange
    }

    public final class VisibilityView: NSView {
        var onChange: (@MainActor (Bool) -> Void)?
        private var observer: NSObjectProtocol?
        private var lastReported: Bool?

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else {
                report(false)
                return
            }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportWindowState() }
            }
            reportWindowState()
        }

        private func reportWindowState() {
            report(window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false)
        }

        private func report(_ visible: Bool) {
            guard visible != lastReported else { return }
            lastReported = visible
            onChange?(visible)
        }
    }
}
