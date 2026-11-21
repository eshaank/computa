import AppKit
import ComputaCore
import SwiftUI

/// What to draw for a process group.
public enum AppIcon {
    case image(NSImage)
    /// An SF Symbol name.
    case symbol(String)
}

/// Finds the icon for a process group. The local provider reads app bundles on this Mac; a
/// remote daemon's apps will need another implementation.
@MainActor
public protocol AppIconProviding: AnyObject {
    func icon(for group: ProcessGroup) -> AppIcon
}

extension AppIcon {
    /// The symbol for a group that is not an app: a gear for the system group, a terminal glyph
    /// for the rest.
    static func fallback(for group: ProcessGroup) -> AppIcon {
        .symbol(group.isSystem ? "gearshape.fill" : "terminal.fill")
    }
}

/// Icons from the app bundles on this Mac, cached by bundle path.
@MainActor
public final class LocalAppIconProvider: AppIconProviding {
    private var cache: [String: NSImage] = [:]
    private let fileManager = FileManager.default

    public init() {}

    public func icon(for group: ProcessGroup) -> AppIcon {
        let path = group.bundlePath
        guard !path.isEmpty else { return .fallback(for: group) }
        if let cached = cache[path] { return .image(cached) }
        // NSWorkspace returns a generic icon for a missing path rather than failing, so check
        // that the bundle exists first.
        guard fileManager.fileExists(atPath: path) else { return .fallback(for: group) }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return .image(image)
    }
}

/// A group's icon at the list's size.
struct AppIconView: View {
    let icon: AppIcon
    var size: CGFloat = DashboardMetrics.iconSize

    var body: some View {
        switch icon {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        case .symbol(let name):
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Theme.track)
                .frame(width: size - 2, height: size - 2)
                .overlay(
                    Image(systemName: name)
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(Theme.text.opacity(0.85))
                )
                .frame(width: size, height: size)
        }
    }
}
