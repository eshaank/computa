import Foundation
import Testing

@testable import ComputaCore

@Suite struct FormatTests {
    static let percents: [(Double, Int)] = [
        (0, 0), (0.49, 0), (0.5, 1), (23.6, 24), (41.5, 42), (99.4, 99), (99.5, 100), (100, 100),
        (-3, 0), (130, 100), (Double.nan, 0), (Double.infinity, 0),
    ]

    @Test(arguments: percents)
    func wholePercentRoundsToTheNearestPercent(value: Double, expected: Int) {
        #expect(Format.wholePercent(value) == expected)
        #expect(Format.percent(value) == "\(expected)%")
    }

    @Test func ringFractionMatchesTheShownPercent() {
        #expect(Format.ringFraction(23.6) == 0.24)
        #expect(Format.ringFraction(0) == 0)
        #expect(Format.ringFraction(250) == 1)
    }

    @Test func ringPercentMatchesTheDaemonsUsedOverTotal() {
        // 22_548_578_304 of 36 GiB is 58.33%, which must show as 58.
        let memory = Fixtures.sample.memory
        #expect(Format.percent(memory.usedPercent) == "58%")
        // 811 of 994.66 GB is 81.54%.
        #expect(Format.percent(Fixtures.sample.startupVolume!.usedPercent) == "82%")
    }

    static let memorySizes: [(UInt64, String)] = [
        (0, "0 B"), (512, "512 B"), (1023, "1.0 KB"), (1536, "1.5 KB"),
        (15_569_256_448, "14.5 GB"), (UInt64(36) << 30, "36.0 GB"), (UInt64(512) << 20, "512 MB"),
        (UInt64(1) << 40, "1.0 TB"),
    ]

    @Test(arguments: memorySizes)
    func memoryUsesBinaryUnits(bytes: UInt64, expected: String) {
        #expect(Format.memory(bytes) == expected)
    }

    static let storageSizes: [(UInt64, String)] = [
        (999, "999 B"), (1000, "1.0 KB"), (494_000_000_000, "494 GB"),
        (994_662_584_320, "995 GB"), (1_200_000_000_000, "1.2 TB"),
    ]

    @Test(arguments: storageSizes)
    func storageUsesDecimalUnits(bytes: UInt64, expected: String) {
        #expect(Format.storage(bytes) == expected)
    }

    static let rates: [(Double, String)] = [
        (0, "0 B/s"), (850, "850 B/s"), (2_450_000, "2.5 MB/s"), (182_000, "182 KB/s"),
        (-5, "0 B/s"), (Double.nan, "0 B/s"),
    ]

    @Test(arguments: rates)
    func ratesUseDecimalUnitsPerSecond(bytesPerSecond: Double, expected: String) {
        #expect(Format.rate(bytesPerSecond) == expected)
    }

    static let uptimes: [(Double, String)] = [
        (0, "0m"), (59.0, "0m"), (7 * 60.0, "7m"), (5 * 3600 + 12 * 60.0, "5h 12m"),
        (3 * 86_400 + 4 * 3600 + 17 * 60.0, "3d 4h"), (-100, "0m"),
    ]

    @Test(arguments: uptimes)
    func uptimeShowsTheTwoLargestUnits(seconds: Double, expected: String) {
        let boot = Date(timeIntervalSince1970: 1_000_000)
        #expect(Format.uptime(since: boot, now: boot.addingTimeInterval(seconds)) == expected)
    }

    @Test func usageSharesTheTotalsUnit() {
        #expect(Format.memoryUsage(used: 22_548_578_304, total: UInt64(36) << 30) == "21.0 / 36.0 GB")
        #expect(Format.memoryUsage(used: UInt64(512) << 20, total: UInt64(16) << 30) == "0.5 / 16.0 GB")
        #expect(Format.storageUsage(used: 811_000_000_000, total: 994_662_584_320) == "811 / 995 GB")
        #expect(Format.storageUsage(used: 0, total: 0) == "0 / 0 B")
    }

    @Test func batteryDescribesChargeAndState() {
        var battery = BatterySample(chargePercent: 82.4, state: .charging, onACPower: true, minutesRemaining: nil)
        #expect(Format.battery(battery) == "82%, charging")
        battery.state = .discharging
        #expect(Format.battery(battery) == "82%, on battery")
        battery.state = .full
        battery.chargePercent = 100
        #expect(Format.battery(battery) == "100%, full")
    }
}
