import SwiftUI

/// The "Whitby Bay" colours. Dark theme only. Every colour in the UI comes from here.
public enum Theme {
    /// Window background.
    public static let background = Color(hex: 0x272A38)
    /// Panels and capsules drawn on the background.
    public static let panel = Color(hex: 0x20222E)
    /// Selection and ring tracks.
    public static let track = Color(hex: 0x434861)
    public static let text = Color(hex: 0xF7F7EE)
    public static let dimText = Color(hex: 0x66759F)

    public static let cpu = Color(hex: 0x4DF08A)
    public static let memory = Color(hex: 0xB696F7)
    public static let memoryLight = Color(hex: 0xD0B0FB)
    public static let disk = Color(hex: 0xF5F28A)
    public static let network = Color(hex: 0x90ECF6)
    public static let sessions = Color(hex: 0xFF7ED1)
    public static let warning = Color(hex: 0xFF5D57)

    /// The "on" colour of switches.
    public static let accent = memory
    /// Thin dividers between popover sections.
    public static let divider = Color.white.opacity(0.08)
}

/// The soft coloured glow behind bright marks. Every glow in the UI uses these two numbers.
public enum Glow {
    /// How strong the glow colour is, from 0 (none) to 1.
    public static let opacity: Double = 0.15
    public static let radius: CGFloat = 3
}

extension View {
    /// A faint glow in `color`. Pass `isOn: false` for the same layout with no glow.
    func glow(_ color: Color, isOn: Bool = true) -> some View {
        shadow(color: color.opacity(isOn ? Glow.opacity : 0), radius: Glow.radius)
    }
}

extension Color {
    /// A colour from a 24-bit `0xRRGGBB` value, in sRGB.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Sizes taken from the reference popover (a 2x screenshot, so pixels / 2).
public enum Metrics {
    public static let popoverWidth: CGFloat = 248
    public static let panelCornerRadius: CGFloat = 16
    public static let sidePadding: CGFloat = 16
    public static let ringDiameter: CGFloat = 60
    public static let ringLineWidth: CGFloat = 4.5
    public static let rowHeight: CGFloat = 32
    public static let capsuleHeight: CGFloat = 44
    public static let gapToCapsule: CGFloat = 10
}

extension Font {
    static let rowLabel = Font.system(size: 13, weight: .medium)
    static let rowValue = Font.system(size: 12, weight: .regular).monospacedDigit()
    static let ringLabel = Font.system(size: 8.5, weight: .semibold)
    static let ringValue = Font.system(size: 12, weight: .semibold).monospacedDigit()
    static let ringDetail = Font.system(size: 9, weight: .regular).monospacedDigit()
}
