import Foundation
import Testing

@testable import ComputaCore

@Suite struct ProcessListTests {
    static func process(_ pid: Int32, _ name: String, cpu: Double = 0, memory: UInt64 = 0) -> ProcessEntry {
        ProcessEntry(pid: pid, parentPid: 1, name: name, path: "/x/\(name)", cpuPercent: cpu, memoryBytes: memory, residentBytes: 0)
    }

    static func group(_ id: String, _ name: String, cpu: Double, memory: UInt64, _ processes: [ProcessEntry] = []) -> ProcessGroup {
        ProcessGroup(id: id, name: name, bundlePath: "", cpuPercent: cpu, memoryBytes: memory, processes: processes)
    }

    static let groups = [
        group("a", "Alpha", cpu: 5, memory: 900, [process(10, "alpha"), process(11, "Alpha Helper")]),
        group("b", "Bravo", cpu: 50, memory: 100, [process(20, "bravo")]),
        group("c", "Charlie", cpu: 20, memory: 5000, [process(30, "charlie"), process(31, "Renderer"), process(32, "GPU")]),
    ]

    @Test func sortsByCpuLargestFirst() {
        #expect(ProcessList.sorted(Self.groups, by: .cpu).map(\.id) == ["b", "c", "a"])
    }

    @Test func sortsByMemoryLargestFirst() {
        #expect(ProcessList.sorted(Self.groups, by: .memory).map(\.id) == ["c", "a", "b"])
    }

    @Test func sortsEachGroupsProcessesTheSameWay() {
        let group = Self.group("g", "G", cpu: 0, memory: 0, [
            Self.process(1, "small", cpu: 1, memory: 300),
            Self.process(2, "big", cpu: 9, memory: 100),
            Self.process(3, "mid", cpu: 4, memory: 200),
        ])
        #expect(ProcessList.sorted([group], by: .cpu)[0].processes.map(\.pid) == [2, 3, 1])
        #expect(ProcessList.sorted([group], by: .memory)[0].processes.map(\.pid) == [1, 3, 2])
    }

    @Test func equalValuesAreOrderedByNameThenIdWhateverTheInputOrder() {
        let tied = [
            Self.group("z2", "zed", cpu: 3, memory: 7),
            Self.group("m", "Mike", cpu: 3, memory: 7),
            Self.group("z1", "Zed", cpu: 3, memory: 7),
        ]
        let expected = ["m", "z1", "z2"]
        #expect(ProcessList.sorted(tied, by: .cpu).map(\.id) == expected)
        #expect(ProcessList.sorted(tied.reversed(), by: .cpu).map(\.id) == expected)
        #expect(ProcessList.sorted(tied.shuffled(), by: .memory).map(\.id) == expected)

        let processes = [Self.process(9, "b"), Self.process(4, "a"), Self.process(2, "b")]
        #expect(ProcessList.sorted(processes, by: .memory).map(\.pid) == [4, 2, 9])
    }

    @Test func filtersByGroupNameIgnoringCase() {
        #expect(ProcessList.filtered(Self.groups, query: "bRaV").map(\.id) == ["b"])
    }

    @Test func keepsAGroupWhenOnlyOneOfItsProcessesMatches() {
        let result = ProcessList.filtered(Self.groups, query: "renderer")
        #expect(result.map(\.id) == ["c"])
        #expect(result[0].processes.count == 3, "a matching group keeps all its processes")
        #expect(ProcessList.filtered(Self.groups, query: "helper").map(\.id) == ["a"])
    }

    @Test func noMatchGivesNothingAndABlankQueryGivesEverything() {
        #expect(ProcessList.filtered(Self.groups, query: "xyz").isEmpty)
        #expect(ProcessList.filtered(Self.groups, query: "  ").map(\.id) == ["a", "b", "c"])
    }

    @Test func visibleFiltersThenSorts() {
        #expect(ProcessList.visible(Self.groups, query: "a", metric: .cpu).map(\.id) == ["b", "c", "a"])
        #expect(ProcessList.visible(Self.groups, query: "alpha", metric: .memory).map(\.id) == ["a"])
    }

    @Test func badgeCountsProcessesBeyondTheFirst() {
        #expect(Self.groups[0].extraProcessCount == 1)
        #expect(Self.groups[0].badge == "+1")
        #expect(Self.groups[2].badge == "+2")
        #expect(Self.groups[1].badge == nil, "one process: no badge")
        #expect(Self.group("e", "Empty", cpu: 0, memory: 0).badge == nil)
        #expect(Fixtures.processes.groups[0].badge == "+113")
    }

    @Test func valueTextShowsCpuAboveOneHundredAndMemoryInBinaryUnits() {
        #expect(ProcessList.valueText(312.46, .cpu) == "312.5%")
        #expect(ProcessList.valueText(-1, .cpu) == "0.0%")
        #expect(ProcessList.valueText(Double(1536 << 20), .memory) == "1.5 GB")
    }
}
