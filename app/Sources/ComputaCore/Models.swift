import Foundation

/// Facts about the machine a daemon runs on. They do not change while it runs.
public struct HostInfo: Sendable, Equatable {
    public var hostname: String
    public var model: String
    public var chip: String
    public var osVersion: String
    public var daemonVersion: String
    public var memoryTotalBytes: UInt64
    public var coreGroups: [CoreGroup]
    public var bootTime: Date
    public var sampleIntervalMilliseconds: UInt32
    public var historyCapacity: UInt32

    public init(
        hostname: String, model: String, chip: String, osVersion: String, daemonVersion: String,
        memoryTotalBytes: UInt64, coreGroups: [CoreGroup], bootTime: Date,
        sampleIntervalMilliseconds: UInt32, historyCapacity: UInt32
    ) {
        self.hostname = hostname
        self.model = model
        self.chip = chip
        self.osVersion = osVersion
        self.daemonVersion = daemonVersion
        self.memoryTotalBytes = memoryTotalBytes
        self.coreGroups = coreGroups
        self.bootTime = bootTime
        self.sampleIntervalMilliseconds = sampleIntervalMilliseconds
        self.historyCapacity = historyCapacity
    }
}

public enum CoreKind: Sendable, Equatable {
    case unspecified, performance, efficiency
}

public struct CoreGroup: Sendable, Equatable {
    public var kind: CoreKind
    public var name: String
    public var coreCount: Int

    public init(kind: CoreKind, name: String, coreCount: Int) {
        self.kind = kind
        self.name = name
        self.coreCount = coreCount
    }
}

/// One reading of the whole system.
public struct SystemSample: Sendable, Equatable {
    public var time: Date
    public var cpu: CpuSample
    public var memory: MemorySample
    /// The startup volume first.
    public var volumes: [VolumeSample]
    public var diskReadBytesPerSecond: Double
    public var diskWriteBytesPerSecond: Double
    public var network: NetworkSample
    /// Nil on machines without a battery.
    public var battery: BatterySample?

    /// The startup volume, if the daemon reported any volume.
    public var startupVolume: VolumeSample? { volumes.first }
}

public struct CpuSample: Sendable, Equatable {
    public var usagePercent: Double
    public var userPercent: Double
    public var systemPercent: Double
    public var cores: [CoreSample]
    public var loadAverages: [Double]
}

public struct CoreSample: Sendable, Equatable {
    public var index: Int
    public var kind: CoreKind
    public var usagePercent: Double
}

public enum MemoryPressure: Sendable, Equatable {
    case unknown, normal, warning, critical
}

public struct MemorySample: Sendable, Equatable {
    public var totalBytes: UInt64
    /// What Activity Monitor calls "Memory Used".
    public var usedBytes: UInt64
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var cachedBytes: UInt64
    public var freeBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    public var pressure: MemoryPressure

    /// Used memory as a share of total, 0...100. Zero when the total is unknown.
    public var usedPercent: Double { Ratio.percent(usedBytes, of: totalBytes) }
}

public struct VolumeSample: Sendable, Equatable {
    public var name: String
    public var mountPoint: String
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var availableBytes: UInt64

    /// Used space as a share of total, 0...100. Zero when the total is unknown.
    public var usedPercent: Double { Ratio.percent(usedBytes, of: totalBytes) }
}

public struct NetworkSample: Sendable, Equatable {
    public var receiveBytesPerSecond: Double
    public var sendBytesPerSecond: Double
    public var interfaces: [NetworkInterfaceSample]
}

public struct NetworkInterfaceSample: Sendable, Equatable {
    public var name: String
    public var addresses: [String]
    public var receiveBytesPerSecond: Double
    public var sendBytesPerSecond: Double
    public var receivedBytesTotal: UInt64
    public var sentBytesTotal: UInt64
}

public enum BatteryState: Sendable, Equatable {
    case unknown, charging, discharging, full
}

public struct BatterySample: Sendable, Equatable {
    public var chargePercent: Double
    public var state: BatteryState
    public var onACPower: Bool
    /// Minutes until empty or full. Nil while macOS is still working it out.
    public var minutesRemaining: Int?
}

/// Stored samples for charts, oldest first.
public struct HistorySeries: Sendable, Equatable {
    public var points: [HistoryPoint]
    public var stepMilliseconds: UInt32
}

public struct HistoryPoint: Sendable, Equatable {
    public var time: Date
    public var cpuUsagePercent: Double
    public var cpuUserPercent: Double
    public var cpuSystemPercent: Double
    public var memoryUsedBytes: UInt64
    public var memoryAppBytes: UInt64
    public var memoryWiredBytes: UInt64
    public var memoryCompressedBytes: UInt64
    public var swapUsedBytes: UInt64
    public var networkReceiveBytesPerSecond: Double
    public var networkSendBytesPerSecond: Double
    public var diskReadBytesPerSecond: Double
    public var diskWriteBytesPerSecond: Double
}

/// Safe share calculations: a zero or missing total never yields NaN.
public enum Ratio {
    /// `part` as a percentage of `total`, clamped to 0...100. Zero when `total` is zero.
    public static func percent(_ part: UInt64, of total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(100, Double(part) / Double(total) * 100)
    }
}
