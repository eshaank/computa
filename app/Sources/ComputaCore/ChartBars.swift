import Foundation

/// One bar on the dashboard chart. A bar is a stack of parts going up from the baseline, and on
/// two-series charts (network, disk) a second stack going down from it.
public struct ChartBar: Sendable, Equatable {
    public var time: Date
    /// Bottom first. Their sum is the bar's height.
    public var parts: [Double]
    /// Going down from the baseline, nearest first. Empty on one-direction charts.
    public var mirroredParts: [Double]

    public init(time: Date, parts: [Double], mirroredParts: [Double] = []) {
        self.time = time
        self.parts = parts
        self.mirroredParts = mirroredParts
    }

    public var total: Double { parts.reduce(0, +) }
    public var mirroredTotal: Double { mirroredParts.reduce(0, +) }
}

/// Everything needed to draw a chart.
public struct ChartModel: Sendable, Equatable {
    /// Oldest first.
    public var bars: [ChartBar]
    public var scale: ChartScale
    /// True when bars also go down from a middle baseline.
    public var isMirrored: Bool
    /// The chart is divided into this many equal slots, newest on the right. With fewer bars
    /// than slots the left stays empty, so a short history never shows as a few fat bars.
    public var slotCount: Int

    public init(bars: [ChartBar], scale: ChartScale, isMirrored: Bool, slotCount: Int) {
        self.bars = bars
        self.scale = scale
        self.isMirrored = isMirrored
        self.slotCount = slotCount
    }
}

/// Turns history points into chart bars and picks the scale for each tab.
public enum ChartBuilder {
    /// - Parameters:
    ///   - memoryTotal: The machine's memory, the top of the memory chart. Zero when unknown.
    ///   - slotCount: The number of bars the chart has room for, normally the `max_points` asked for.
    public static func model(
        for tab: DashboardTab, points: [HistoryPoint], memoryTotal: UInt64, slotCount: Int
    ) -> ChartModel {
        let bars = bars(for: tab, points: points).suffix(max(1, slotCount))
        let largest = bars.map { max($0.total, $0.mirroredTotal) }.max() ?? 0
        let scale: ChartScale
        switch tab {
        case .cpu: scale = .percent
        case .memory: scale = .memory(total: memoryTotal, largest: largest)
        case .network, .disk: scale = .rate(largest: largest, guideCount: 2)
        }
        return ChartModel(
            bars: Array(bars), scale: scale, isMirrored: tab.isMirroredChart, slotCount: max(1, slotCount)
        )
    }

    /// One bar per point, oldest first.
    ///
    /// - CPU: system (bottom) and user, adding up to the usage percent.
    /// - Memory: wired (bottom), compressed and app, adding up to memory used.
    /// - Network: received up, sent down. Disk: read up, written down.
    public static func bars(for tab: DashboardTab, points: [HistoryPoint]) -> [ChartBar] {
        points.map { point in
            switch tab {
            case .cpu: cpuBar(point)
            case .memory: memoryBar(point)
            case .network:
                ChartBar(
                    time: point.time, parts: [clean(point.networkReceiveBytesPerSecond)],
                    mirroredParts: [clean(point.networkSendBytesPerSecond)]
                )
            case .disk:
                ChartBar(
                    time: point.time, parts: [clean(point.diskReadBytesPerSecond)],
                    mirroredParts: [clean(point.diskWriteBytesPerSecond)]
                )
            }
        }
    }

    /// The user part is the usage left over after system time, so the stack is exactly the usage
    /// even when the daemon's parts are rounded differently.
    static func cpuBar(_ point: HistoryPoint) -> ChartBar {
        let usage = min(100, clean(point.cpuUsagePercent))
        let system = min(usage, clean(point.cpuSystemPercent))
        return ChartBar(time: point.time, parts: [system, usage - system])
    }

    /// Wired and compressed are capped by what is left of memory used, and app is the rest, so
    /// the stack is exactly memory used.
    static func memoryBar(_ point: HistoryPoint) -> ChartBar {
        let used = point.memoryUsedBytes
        let wired = min(point.memoryWiredBytes, used)
        let compressed = min(point.memoryCompressedBytes, used - wired)
        let app = used - wired - compressed
        return ChartBar(time: point.time, parts: [Double(wired), Double(compressed), Double(app)])
    }

    private static func clean(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}

extension DashboardTab {
    /// Network and disk charts show two series, one above and one below the baseline.
    public var isMirroredChart: Bool {
        switch self {
        case .network, .disk: true
        case .cpu, .memory: false
        }
    }
}
