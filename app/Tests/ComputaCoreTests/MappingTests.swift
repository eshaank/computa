import Foundation
import Testing

@testable import ComputaCore

@Suite struct MappingTests {
    static func message(battery: Bool) -> Computa_V1_SystemSample {
        Computa_V1_SystemSample.with {
            $0.unixMs = 1_795_000_000_500
            $0.cpu = .with {
                $0.usagePercent = 37.5
                $0.userPercent = 25
                $0.systemPercent = 12.5
                $0.cores = [.with { $0.index = 3; $0.kind = .efficiency; $0.usagePercent = 80 }]
                $0.loadAverage1M = 1.5
                $0.loadAverage15M = 0.5
            }
            $0.memory = .with {
                $0.totalBytes = 32_000
                $0.usedBytes = 8_000
                $0.swapUsedBytes = 7
                $0.pressure = .warning
            }
            $0.volumes = [
                .with { $0.name = "Macintosh HD"; $0.mountPoint = "/"; $0.totalBytes = 1000; $0.usedBytes = 905; $0.availableBytes = 95 },
                .with { $0.name = "Backup"; $0.mountPoint = "/Volumes/Backup"; $0.totalBytes = 10 },
            ]
            $0.diskActivity = .with { $0.readBytesPerSec = 11; $0.writeBytesPerSec = 22 }
            $0.network = .with {
                $0.rxBytesPerSec = 1500
                $0.txBytesPerSec = 300
                $0.interfaces = [.with { $0.name = "en0"; $0.addresses = ["10.0.0.2"]; $0.rxBytesTotal = 99 }]
            }
            if battery {
                $0.battery = .with { $0.chargePercent = 64; $0.state = .charging; $0.onAcPower = true; $0.minutesRemaining = 45 }
            }
        }
    }

    @Test func mapsEveryPartOfASample() {
        let sample = SystemSample(Self.message(battery: true))

        #expect(sample.time == Date(timeIntervalSince1970: 1_795_000_000.5))
        #expect(sample.cpu.usagePercent == 37.5)
        #expect(sample.cpu.userPercent == 25)
        #expect(sample.cpu.systemPercent == 12.5)
        #expect(sample.cpu.cores == [CoreSample(index: 3, kind: .efficiency, usagePercent: 80)])
        #expect(sample.cpu.loadAverages == [1.5, 0, 0.5])
        #expect(sample.memory.usedBytes == 8_000)
        #expect(sample.memory.swapUsedBytes == 7)
        #expect(sample.memory.pressure == .warning)
        #expect(sample.memory.usedPercent == 25)
        #expect(sample.volumes.map(\.mountPoint) == ["/", "/Volumes/Backup"])
        #expect(sample.startupVolume?.name == "Macintosh HD")
        #expect(sample.startupVolume?.usedPercent == 90.5)
        #expect(sample.diskReadBytesPerSecond == 11)
        #expect(sample.diskWriteBytesPerSecond == 22)
        #expect(sample.network.receiveBytesPerSecond == 1500)
        #expect(sample.network.sendBytesPerSecond == 300)
        #expect(sample.network.interfaces.first?.addresses == ["10.0.0.2"])
        #expect(sample.network.interfaces.first?.receivedBytesTotal == 99)
        #expect(sample.battery == BatterySample(chargePercent: 64, state: .charging, onACPower: true, minutesRemaining: 45))
    }

    @Test func absentBatteryMapsToNil() {
        let sample = SystemSample(Self.message(battery: false))
        #expect(sample.battery == nil)
    }

    @Test func batteryWithoutAnEstimateHasNoMinutesRemaining() {
        var message = Self.message(battery: true)
        message.battery.clearMinutesRemaining()
        #expect(SystemSample(message).battery?.minutesRemaining == nil)
    }

    @Test func emptySampleHasZeroPercentagesNotNaN() {
        let sample = SystemSample(Computa_V1_SystemSample())
        #expect(sample.memory.usedPercent == 0)
        #expect(sample.startupVolume == nil)
        #expect(sample.battery == nil)
        #expect(sample.memory.pressure == .unknown)
    }

    @Test func mapsHostFacts() {
        let host = HostInfo(.with {
            $0.hostname = "mini"
            $0.chip = "Apple M1"
            $0.memoryTotalBytes = 16
            $0.bootUnixMs = 1_000
            $0.sampleIntervalMs = 1000
            $0.historyCapacity = 3600
            $0.coreGroups = [.with { $0.kind = .performance; $0.name = "Performance"; $0.coreCount = 4 }]
        })
        #expect(host.hostname == "mini")
        #expect(host.chip == "Apple M1")
        #expect(host.bootTime == Date(timeIntervalSince1970: 1))
        #expect(host.coreGroups == [CoreGroup(kind: .performance, name: "Performance", coreCount: 4)])
        #expect(host.sampleIntervalMilliseconds == 1000)
        #expect(host.historyCapacity == 3600)
    }

    @Test func mapsHistoryOldestFirst() {
        let history = HistorySeries(.with {
            $0.stepMs = 2000
            $0.points = [
                .with { $0.unixMs = 1000; $0.cpuUsagePercent = 10; $0.netRxBytesPerSec = 5 },
                .with { $0.unixMs = 3000; $0.memoryUsedBytes = 42; $0.diskWriteBytesPerSec = 9 },
            ]
        })
        #expect(history.stepMilliseconds == 2000)
        #expect(history.points.map(\.time) == [Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 3)])
        #expect(history.points[0].cpuUsagePercent == 10)
        #expect(history.points[0].networkReceiveBytesPerSecond == 5)
        #expect(history.points[1].memoryUsedBytes == 42)
        #expect(history.points[1].diskWriteBytesPerSecond == 9)
    }

    @Test func unknownEnumValuesMapToUnknown() {
        #expect(MemoryPressure(.UNRECOGNIZED(9)) == .unknown)
        #expect(BatteryState(.UNRECOGNIZED(9)) == .unknown)
        #expect(CoreKind(.UNRECOGNIZED(9)) == .unspecified)
    }
}
