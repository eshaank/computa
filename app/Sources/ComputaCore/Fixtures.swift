import Foundation

/// Made-up but realistic values for previews, snapshots and tests.
public enum Fixtures {
    public static let now = Date(timeIntervalSince1970: 1_795_000_000)

    public static let host = HostInfo(
        hostname: "Morgans-MacBook-Pro",
        model: "Mac15,8",
        chip: "Apple M3 Max",
        osVersion: "macOS 27.0.1",
        daemonVersion: "0.2.0",
        memoryTotalBytes: 36 * gibibyte,
        coreGroups: [
            CoreGroup(kind: .performance, name: "Performance", coreCount: 10),
            CoreGroup(kind: .efficiency, name: "Efficiency", coreCount: 4),
        ],
        bootTime: now.addingTimeInterval(-(3 * 86_400 + 4 * 3600 + 17 * 60)),
        sampleIntervalMilliseconds: 1000,
        historyCapacity: 3600
    )

    /// A busy laptop on battery.
    public static let sample = SystemSample(
        time: now,
        cpu: CpuSample(
            usagePercent: 23.6, userPercent: 15.1, systemPercent: 8.5,
            cores: (0..<14).map { CoreSample(index: $0, kind: $0 < 10 ? .performance : .efficiency, usagePercent: 20) },
            loadAverages: [3.1, 2.8, 2.5]
        ),
        memory: MemorySample(
            totalBytes: 36 * gibibyte, usedBytes: 22_548_578_304, appBytes: 14 * gibibyte,
            wiredBytes: 4 * gibibyte, compressedBytes: 3 * gibibyte, cachedBytes: 9 * gibibyte,
            freeBytes: 2 * gibibyte, swapUsedBytes: 0, swapTotalBytes: 0, pressure: .normal
        ),
        volumes: [
            VolumeSample(
                name: "Macintosh HD", mountPoint: "/", totalBytes: 994_662_584_320,
                usedBytes: 811_000_000_000, availableBytes: 183_662_584_320
            )
        ],
        diskReadBytesPerSecond: 1_200_000,
        diskWriteBytesPerSecond: 340_000,
        network: NetworkSample(receiveBytesPerSecond: 2_450_000, sendBytesPerSecond: 182_000, interfaces: []),
        battery: BatterySample(chargePercent: 82.4, state: .discharging, onACPower: false, minutesRemaining: 312)
    )

    /// A desktop without a battery, under memory pressure.
    public static var desktopUnderPressure: SystemSample {
        var sample = sample
        sample.battery = nil
        sample.cpu.usagePercent = 91.2
        sample.memory.usedBytes = 34 * gibibyte
        sample.memory.pressure = .warning
        return sample
    }

    private static let gibibyte: UInt64 = 1 << 30
}
