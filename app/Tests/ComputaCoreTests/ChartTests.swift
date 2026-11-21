import Foundation
import Testing

@testable import ComputaCore

@Suite struct ChartScaleTests {
    @Test func percentRunsToOneHundredWithQuarterGuides() {
        let scale = ChartScale.percent
        #expect(scale.upperBound == 100)
        #expect(scale.guides.map(\.value) == [25, 50, 75, 100])
        #expect(scale.guides.map(\.label) == ["25%", "50%", "75%", "100%"])
        #expect(scale.fraction(50) == 0.5)
        #expect(scale.fraction(150) == 1)
        #expect(scale.fraction(.nan) == 0)
    }

    @Test func memoryRunsToTotalWithQuarterGuides() {
        let scale = ChartScale.memory(total: 36 << 30, largest: 20e9)
        #expect(scale.upperBound == Double(36 << 30))
        #expect(scale.guides.map(\.label) == ["9.0 GB", "18.0 GB", "27.0 GB", "36.0 GB"])
    }

    @Test func memoryWithoutTotalFitsTheDataAndNeverCollapses() {
        #expect(ChartScale.memory(total: 0, largest: 0).upperBound == Double(1 << 30))
        #expect(ChartScale.memory(total: 0, largest: 8e9).upperBound == 8e9)
    }

    @Test func rateFitsTheLargestValueWithRoundGuides() {
        let scale = ChartScale.rate(largest: 2_450_000)
        #expect(scale.upperBound >= 2_450_000)
        #expect(scale.guides.map(\.label) == ["800 KB/s", "1.6 MB/s", "2.4 MB/s", "3.2 MB/s"])
        #expect(scale.guides.last?.value == scale.upperBound)

        let two = ChartScale.rate(largest: 2_450_000, guideCount: 2)
        #expect(two.guides.map(\.label) == ["1.5 MB/s", "3.0 MB/s"])
    }

    @Test func rateGuidesAreEvenlySpaced() {
        for largest in [1.0, 999, 12_345, 7_800_000, 3e9] {
            let scale = ChartScale.rate(largest: largest)
            let values = scale.guides.map(\.value)
            #expect(scale.upperBound >= largest)
            #expect(values.count == 4)
            for (index, value) in values.enumerated() {
                #expect(abs(value - values[0] * Double(index + 1)) < 1e-6 * scale.upperBound)
            }
        }
    }

    @Test func allZeroOrInvalidRatesStillGetASmallScale() {
        for largest in [0, -5, Double.nan, Double.infinity] {
            let scale = ChartScale.rate(largest: largest)
            #expect(scale.upperBound == 1000, "largest \(largest)")
            #expect(scale.guides.map(\.label) == ["250 B/s", "500 B/s", "750 B/s", "1.0 KB/s"])
        }
    }
}

@Suite struct ChartBarTests {
    static func point(
        cpu: Double = 0, user: Double = 0, system: Double = 0, used: UInt64 = 0, wired: UInt64 = 0,
        compressed: UInt64 = 0, rx: Double = 0, tx: Double = 0, read: Double = 0, write: Double = 0, at seconds: Double = 0
    ) -> HistoryPoint {
        HistoryPoint(
            time: Date(timeIntervalSince1970: seconds), cpuUsagePercent: cpu, cpuUserPercent: user,
            cpuSystemPercent: system, memoryUsedBytes: used, memoryAppBytes: used &- wired &- compressed,
            memoryWiredBytes: wired, memoryCompressedBytes: compressed, swapUsedBytes: 0,
            networkReceiveBytesPerSecond: rx, networkSendBytesPerSecond: tx,
            diskReadBytesPerSecond: read, diskWriteBytesPerSecond: write
        )
    }

    @Test func cpuStacksSystemUnderUserAndAddsUpToUsage() {
        let bar = ChartBuilder.bars(for: .cpu, points: [Self.point(cpu: 37.3, user: 25.1, system: 12.2)])[0]
        #expect(bar.parts.count == 2)
        #expect(bar.parts[0] == 12.2)
        #expect(abs(bar.total - 37.3) < 1e-9)
        #expect(bar.mirroredParts.isEmpty)
    }

    @Test func cpuPartsNeverExceedUsageEvenWhenTheDaemonsPartsDisagree() {
        let bar = ChartBuilder.bars(for: .cpu, points: [Self.point(cpu: 10, user: 9, system: 14)])[0]
        #expect(bar.parts == [10, 0])
        #expect(bar.total == 10)
    }

    @Test func memoryStacksWiredCompressedAppAndAddsUpToUsed() {
        let bar = ChartBuilder.bars(for: .memory, points: [Self.point(used: 21_000, wired: 4_000, compressed: 3_000)])[0]
        #expect(bar.parts == [4_000, 3_000, 14_000])
        #expect(bar.total == 21_000)

        let odd = ChartBuilder.bars(for: .memory, points: [Self.point(used: 5_000, wired: 4_000, compressed: 3_000)])[0]
        #expect(odd.total == 5_000, "parts are capped so the stack is memory used")
        #expect(odd.parts.allSatisfy { $0 >= 0 })
    }

    @Test func networkAndDiskGoUpAndDown() {
        let p = Self.point(rx: 900, tx: 100, read: 50, write: -3)
        let net = ChartBuilder.bars(for: .network, points: [p])[0]
        #expect(net.parts == [900] && net.mirroredParts == [100])
        let disk = ChartBuilder.bars(for: .disk, points: [p])[0]
        #expect(disk.parts == [50] && disk.mirroredParts == [0], "negative rates draw as zero")
    }

    @Test func modelKeepsTheNewestBarsAndScalesToTheirLargestValue() {
        let points = (0..<120).map { Self.point(rx: Double($0) * 1000, tx: 500, at: Double($0)) }
        let model = ChartBuilder.model(for: .network, points: points, memoryTotal: 0, slotCount: 90)
        #expect(model.bars.count == 90)
        #expect(model.bars.first?.time == Date(timeIntervalSince1970: 30))
        #expect(model.isMirrored)
        #expect(model.scale.upperBound >= 119_000)
        #expect(model.scale.guides.count == 2)
    }

    @Test func aSinglePointKeepsAllSlots() {
        let model = ChartBuilder.model(for: .cpu, points: [Self.point(cpu: 40, user: 30, system: 10)], memoryTotal: 0, slotCount: 90)
        #expect(model.bars.count == 1)
        #expect(model.slotCount == 90, "one point is one narrow bar at the right, not a full-width bar")
        #expect(model.scale == .percent)
    }

    @Test func emptyHistoryGivesNoBarsAndAUsableScale() {
        let model = ChartBuilder.model(for: .disk, points: [], memoryTotal: 0, slotCount: 90)
        #expect(model.bars.isEmpty)
        #expect(model.scale.upperBound == ChartScale.minimumRate)
        let memory = ChartBuilder.model(for: .memory, points: [], memoryTotal: 16 << 30, slotCount: 90)
        #expect(memory.scale.upperBound == Double(16 << 30))
    }
}
