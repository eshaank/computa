import Foundation
import Testing

@testable import ComputaCore

@Suite struct ProcessFiguresTests {
    static func process(
        _ pid: Int32, footprint: UInt64, resident: UInt64, down: Double = 0, up: Double = 0
    ) -> ProcessEntry {
        ProcessEntry(
            pid: pid, parentPid: 1, name: "p\(pid)", path: "/p\(pid)", cpuPercent: 0, memoryBytes: footprint,
            residentBytes: resident, receiveBytesPerSecond: down, sendBytesPerSecond: up
        )
    }

    static func group(_ id: String, _ processes: [ProcessEntry], footprint: UInt64? = nil) -> ProcessGroup {
        ProcessGroup(
            id: id, name: id, bundlePath: "", cpuPercent: 0,
            memoryBytes: footprint ?? processes.reduce(0) { $0 + $1.memoryBytes }, processes: processes
        )
    }

    @Test func compressedOrSwappedIsFootprintMinusResidentNeverBelowZero() {
        #expect(Self.process(1, footprint: 5_000, resident: 2_000).compressedOrSwappedBytes == 3_000)
        // Shared pages count in full in the resident size, so it can exceed the footprint.
        #expect(Self.process(2, footprint: 1_000, resident: 4_000).compressedOrSwappedBytes == 0)
        #expect(UInt64(3).subtractingClamped(7) == 0)
        #expect(UInt64(7).subtractingClamped(3) == 4)
    }

    @Test func aGroupsFiguresAgreeWithEachOther() {
        let group = Self.group("g", [
            Self.process(1, footprint: 8 << 30, resident: 2 << 30),
            Self.process(2, footprint: 1 << 30, resident: 3 << 30),
        ])
        // Resident is summed from the processes; the difference uses the group's footprint.
        #expect(group.residentBytes == 5 << 30)
        #expect(group.compressedOrSwappedBytes == 4 << 30)
        let figures = MemoryFigures(group, residentReported: true)
        #expect(figures == MemoryFigures(resident: 5 << 30, footprint: 9 << 30, residentReported: true))
        #expect(figures.mem == "5.0 GB")
        #expect(figures.compressedOrSwapped == "4.0 GB")
        #expect(figures.footprint == "9.0 GB")
    }

    @Test func aGroupIgnoresTheDaemonsGroupResidentFieldAndSumsItsProcesses() {
        // An older daemon sends ProcessGroup.resident_bytes as 0; the group must not show 0.
        let snapshot = ProcessSnapshot(Computa_V1_ProcessSnapshot.with {
            $0.groups = [.with {
                $0.id = "g"
                $0.memoryBytes = 900
                $0.residentBytes = 0
                $0.processes = [.with { $0.pid = 1; $0.memoryBytes = 900; $0.residentBytes = 400 }]
            }]
        })
        #expect(snapshot.groups[0].residentBytes == 400)
        #expect(snapshot.reportsResidentSize)
    }

    @Test func withoutResidentSizesMemShowsNotReportedAndSortsByFootprint() {
        let small = Self.group("small", [Self.process(1, footprint: 100, resident: 0)])
        let large = Self.group("large", [Self.process(2, footprint: 900, resident: 0)])
        let snapshot = ProcessSnapshot(time: Fixtures.now, groups: [small, large], hidden: nil, processCount: 2)
        #expect(!snapshot.reportsResidentSize)
        let figures = MemoryFigures(large, residentReported: false)
        #expect(figures.mem == MemoryFigures.notReported)
        #expect(figures.compressedOrSwapped == MemoryFigures.notReported)
        #expect(figures.footprint == "900 B")
        #expect(ProcessList.sorted([small, large], by: .memory, residentReported: false).map(\.id) == ["large", "small"])
    }

    @Test func networkSortsByTotalTrafficAndShowsDownAndUp() {
        let quiet = Self.group("quiet", [Self.process(1, footprint: 0, resident: 0, down: 100, up: 100)])
        let uploader = Self.group("up", [Self.process(2, footprint: 0, resident: 0, down: 10, up: 5_000)])
        let both = Self.group("both", [
            Self.process(3, footprint: 0, resident: 0, down: 1_000, up: 0),
            Self.process(4, footprint: 0, resident: 0, down: 2_400_000, up: 300),
        ])
        #expect(ProcessList.sorted([quiet, uploader, both], by: .network).map(\.id) == ["both", "up", "quiet"])
        #expect(ProcessList.sorted([both], by: .network)[0].processes.map(\.pid) == [4, 3])
        #expect(both.receiveBytesPerSecond == 2_401_000)
        #expect(TrafficFigures(both) == TrafficFigures(receive: 2_401_000, send: 300))
        #expect(TrafficFigures(both).down == "2.4 MB/s")
        #expect(TrafficFigures(both).up == "300 B/s")
        #expect(ProcessList.valueText(ProcessList.value(both, .network), .network) == "2.4 MB/s")
    }

    @Test func trafficAvailabilityFromTheDaemonsStatus() {
        #expect(TrafficAvailability(nil) == .daemonNeedsUpdate)
        #expect(TrafficAvailability(ProcessNetworkStatus(available: false)) == .measuring)
        #expect(TrafficAvailability(ProcessNetworkStatus(available: false, problem: "  ")) == .measuring)
        #expect(TrafficAvailability(ProcessNetworkStatus(available: false, problem: "no nettop")) == .problem("no nettop"))
        #expect(TrafficAvailability(ProcessNetworkStatus(available: true)) == .available)
    }

    @Test func memoryLegendShowsWhatTheCompressorHoldsAndSwap() {
        var memory = Fixtures.sample.memory
        memory.compressedBytes = 9_700 << 20
        memory.compressorStoredBytes = 19_700 << 20
        memory.swapUsedBytes = 22_200 << 20
        memory.swapTotalBytes = 23_500 << 20
        #expect(MemoryLegend.compressed(memory) == "9.5 GB holding 19.2 GB")
        #expect(MemoryLegend.swap(memory) == "21.7 of 22.9 GB")
        // An older daemon sends no stored figure: show the RAM figure alone, never "holding 0 B".
        memory.compressorStoredBytes = 0
        #expect(MemoryLegend.compressed(memory) == "9.5 GB")
        memory.swapTotalBytes = 0
        #expect(MemoryLegend.swap(memory) == "none")
    }

    @Test func mapsTheNewProcessAndMemoryFields() {
        let snapshot = ProcessSnapshot(Computa_V1_ProcessSnapshot.with {
            $0.network = .with { $0.available = false; $0.problem = "measuring failed" }
            $0.groups = [.with {
                $0.id = "g"
                $0.rxBytesPerSec = 1
                $0.processes = [.with { $0.pid = 7; $0.rxBytesPerSec = 1_500; $0.txBytesPerSec = 250 }]
            }]
        })
        #expect(snapshot.network == ProcessNetworkStatus(available: false, problem: "measuring failed"))
        #expect(snapshot.groups[0].processes[0].receiveBytesPerSecond == 1_500)
        #expect(snapshot.groups[0].processes[0].sendBytesPerSecond == 250)
        // Summed from the processes, not the group's own field.
        #expect(snapshot.groups[0].receiveBytesPerSecond == 1_500)
        // An old daemon sends no status at all.
        #expect(ProcessSnapshot(Computa_V1_ProcessSnapshot()).network == nil)

        let memory = MemorySample(Computa_V1_Memory.with { $0.compressedBytes = 10; $0.compressorStoredBytes = 25 })
        #expect(memory.compressorStoredBytes == 25)
        #expect(MemorySample(Computa_V1_Memory()).compressorStoredBytes == 0)
    }
}
