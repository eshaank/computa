import Foundation

/// A horizontal guide line on a chart and the text of its label.
public struct ChartGuide: Sendable, Equatable {
    public var value: Double
    public var label: String

    public init(value: Double, label: String) {
        self.value = value
        self.label = label
    }
}

/// The vertical scale of a chart: zero to `upperBound`, with guide lines, lowest first. The
/// last guide is always at `upperBound`.
public struct ChartScale: Sendable, Equatable {
    public var upperBound: Double
    public var guides: [ChartGuide]

    public init(upperBound: Double, guides: [ChartGuide]) {
        self.upperBound = upperBound
        self.guides = guides
    }

    /// How far up the chart `value` sits, 0...1. Invalid values sit at zero.
    public func fraction(_ value: Double) -> Double {
        guard value.isFinite, upperBound > 0 else { return 0 }
        return min(1, max(0, value / upperBound))
    }

    /// 0–100 % with guides at each quarter.
    public static let percent = ChartScale(
        upperBound: 100,
        guides: [25, 50, 75, 100].map { ChartGuide(value: Double($0), label: "\($0)%") }
    )

    /// Zero to the machine's memory, with guides at each quarter, as in the reference. When the
    /// total is unknown, the scale reaches the largest value, and at least 1 GB.
    public static func memory(total: UInt64, largest: Double) -> ChartScale {
        let top = total > 0 ? Double(total) : max(finite(largest), Double(1 << 30))
        let guides = (1...4).map { quarter in
            let value = top * Double(quarter) / 4
            return ChartGuide(value: value, label: Format.memory(UInt64(value)))
        }
        return ChartScale(upperBound: top, guides: guides)
    }

    /// A scale for transfer rates that fits `largest` with `guideCount` evenly spaced guides at
    /// round values, such as 500 KB/s, 1.0 MB/s, 1.5 MB/s, 2.0 MB/s. All-zero data still gets a
    /// small scale (up to 1 KB/s) so the chart has lines to show.
    public static func rate(largest: Double, guideCount: Int = 4) -> ChartScale {
        let count = max(1, guideCount)
        let top = max(finite(largest), minimumRate)
        let step = roundStep(atLeast: top / Double(count))
        let guides = (1...count).map { index in
            let value = step * Double(index)
            return ChartGuide(value: value, label: Format.rate(value))
        }
        return ChartScale(upperBound: step * Double(count), guides: guides)
    }

    /// The smallest top a rate chart gets, in bytes per second.
    public static let minimumRate: Double = 1000

    /// The smallest "round" number at or above `raw`: 1, 1.5, 2, 2.5, 3, 4, 5, 6 or 8 times a
    /// power of ten.
    static func roundStep(atLeast raw: Double) -> Double {
        guard raw.isFinite, raw > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(raw)))
        let mantissa = raw / magnitude
        let round = roundMantissas.first { $0 >= mantissa - 1e-9 } ?? 10
        return round * magnitude
    }

    private static let roundMantissas: [Double] = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}
