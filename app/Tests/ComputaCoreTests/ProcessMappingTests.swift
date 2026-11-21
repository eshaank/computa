import Foundation
import Testing

@testable import ComputaCore

@Suite struct ProcessMappingTests {
    @Test func mapsEveryPartOfASnapshot() {
        let snapshot = ProcessSnapshot(Computa_V1_ProcessSnapshot.with {
            $0.unixMs = 1_795_000_000_250
            $0.processCount = 640
            $0.hidden = .with { $0.processCount = 312 }
            $0.groups = [
                .with {
                    $0.id = "/Applications/Google Chrome.app"
                    $0.name = "Google Chrome"
                    $0.bundlePath = "/Applications/Google Chrome.app"
                    $0.cpuPercent = 412.5
                    $0.memoryBytes = 6_000
                    $0.processes = [
                        .with {
                            $0.pid = 501
                            $0.parentPid = 1
                            $0.name = "Google Chrome"
                            $0.path = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
                            $0.cpuPercent = 400
                            $0.memoryBytes = 5_000
                            $0.residentBytes = 7_000
                        },
                        .with { $0.pid = 502; $0.parentPid = 501; $0.name = "Google Chrome Helper" },
                    ]
                },
                .with { $0.id = "system"; $0.name = "System" },
            ]
        })
        #expect(snapshot.time == Date(timeIntervalSince1970: 1_795_000_000.25))
        #expect(snapshot.processCount == 640)
        #expect(snapshot.hidden == HiddenProcesses(processCount: 312))
        #expect(snapshot.groups.count == 2)

        let chrome = snapshot.groups[0]
        #expect(chrome.id == "/Applications/Google Chrome.app")
        #expect(chrome.name == "Google Chrome")
        #expect(chrome.bundlePath == "/Applications/Google Chrome.app")
        #expect(chrome.cpuPercent == 412.5)
        #expect(chrome.memoryBytes == 6_000)
        #expect(chrome.badge == "+1")
        #expect(chrome.isSystem == false)
        #expect(chrome.processes[0] == ProcessEntry(
            pid: 501, parentPid: 1, name: "Google Chrome",
            path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            cpuPercent: 400, memoryBytes: 5_000, residentBytes: 7_000
        ))
        #expect(chrome.processes[1].parentPid == 501)

        #expect(snapshot.groups[1].isSystem)
        #expect(snapshot.groups[1].bundlePath.isEmpty)
    }

    @Test func missingHiddenMapsToNil() {
        let snapshot = ProcessSnapshot(Computa_V1_ProcessSnapshot.with { $0.processCount = 3 })
        #expect(snapshot.hidden == nil)
        #expect(snapshot.groups.isEmpty)
    }
}
