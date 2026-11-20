import ComputaCore
import SwiftUI

/// The menu bar item: a small glyph and the CPU percentage, or a dash with no live sample.
public struct MenuBarLabel: View {
    let cpuPercent: Double?

    public init(cpuPercent: Double?) {
        self.cpuPercent = cpuPercent
    }

    /// The text beside the glyph.
    public static func text(cpuPercent: Double?) -> String {
        cpuPercent.map(Format.percent) ?? "–"
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: cpuPercent == nil ? "gauge.with.dots.needle.0percent" : "gauge.with.dots.needle.50percent")
            Text(Self.text(cpuPercent: cpuPercent))
                .monospacedDigit()
        }
        .accessibilityLabel(cpuPercent == nil ? "Computa, no data" : "Computa, CPU \(Self.text(cpuPercent: cpuPercent))")
    }
}
