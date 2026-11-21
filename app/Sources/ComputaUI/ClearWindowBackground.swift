import AppKit
import SwiftUI
import os

/// Makes the hosting window draw nothing of its own, so the popover's panel and its separate
/// bottom capsule show on a clear background as in the reference.
///
/// `MenuBarExtra` gives its window a system material background. This hides that material
/// view. If a future macOS changes the window's structure, nothing is hidden and the popover
/// shows on the system background instead; that is logged.
public struct ClearWindowBackground: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> ClearingView { ClearingView() }

    public func updateNSView(_ nsView: ClearingView, context: Context) {}

    public final class ClearingView: NSView {
        private let logger = Logger(subsystem: "app.computa.Computa", category: "window")

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            let root = window.contentView?.superview ?? window.contentView
            let cleared = clearMaterials(in: root)
            if cleared == 0 {
                logger.notice("no material background found in the popover window; the popover shows on the default window background")
            } else {
                logger.debug("cleared \(cleared) material view(s) in the popover window")
            }
        }

        /// Makes every visual-effect view under `view` draw no material and returns how many it
        /// changed. One that contains this view is masked rather than hidden, because hiding it
        /// would hide the popover's own content too; a mask only affects the material.
        private func clearMaterials(in view: NSView?) -> Int {
            guard let view else { return 0 }
            var cleared = 0
            if let effect = view as? NSVisualEffectView {
                if isDescendant(of: effect) {
                    effect.maskImage = Self.transparentMask
                } else {
                    effect.isHidden = true
                    return 1
                }
                cleared = 1
            }
            return view.subviews.reduce(cleared) { $0 + clearMaterials(in: $1) }
        }

        private static let transparentMask = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()
            return true
        }
    }
}
