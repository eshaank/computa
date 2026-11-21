import Foundation

/// Made-up but realistic dashboard data for snapshots and previews: a process list, an hour of
/// history, and a sample with network interfaces and two volumes.
extension Fixtures {
    /// `sample` with interfaces and an external volume, for the Net and Disk tabs.
    public static var dashboardSample: SystemSample {
        var sample = sample
        sample.network.interfaces = [
            NetworkInterfaceSample(
                name: "en0", addresses: ["192.168.1.42", "fd7a:115c:a1e0::2c"],
                receiveBytesPerSecond: 2_410_000, sendBytesPerSecond: 176_000,
                receivedBytesTotal: 48_300_000_000, sentBytesTotal: 6_100_000_000
            ),
            NetworkInterfaceSample(
                name: "utun4", addresses: ["100.64.12.7"],
                receiveBytesPerSecond: 38_000, sendBytesPerSecond: 6_000,
                receivedBytesTotal: 910_000_000, sentBytesTotal: 140_000_000
            ),
        ]
        sample.volumes.append(
            VolumeSample(
                name: "Backup", mountPoint: "/Volumes/Backup", totalBytes: 2_000_000_000_000,
                usedBytes: 1_240_000_000_000, availableBytes: 760_000_000_000
            )
        )
        return sample
    }

    /// `count` points, one per `stepSeconds`, ending at `now`, with smooth made-up variation.
    public static func history(count: Int = 90, stepSeconds: Double = 10) -> HistorySeries {
        let points = (0..<count).map { index in
            let t = Double(index)
            let wave = (sin(t / 6) + 1) / 2
            let jitter = (sin(t * 0.9) + sin(t * 2.3) * 0.4 + 1.4) / 2.8
            let user = 10 + 18 * wave + 6 * jitter
            let system = 5 + 4 * jitter
            let wired: UInt64 = 4 * gibibyte + UInt64(300_000_000 * jitter)
            let compressed: UInt64 = 2 * gibibyte + UInt64(500_000_000 * wave)
            let app: UInt64 = 13 * gibibyte + UInt64(2_000_000_000 * wave) + UInt64(400_000_000 * jitter)
            return HistoryPoint(
                time: now.addingTimeInterval(-stepSeconds * Double(count - 1 - index)),
                cpuUsagePercent: user + system, cpuUserPercent: user, cpuSystemPercent: system,
                memoryUsedBytes: wired + compressed + app, memoryAppBytes: app,
                memoryWiredBytes: wired, memoryCompressedBytes: compressed, swapUsedBytes: 0,
                networkReceiveBytesPerSecond: 400_000 + 2_100_000 * wave * jitter,
                networkSendBytesPerSecond: 60_000 + 240_000 * jitter,
                diskReadBytesPerSecond: 300_000 + 1_600_000 * jitter * jitter,
                diskWriteBytesPerSecond: 120_000 + 700_000 * wave
            )
        }
        return HistorySeries(points: points, stepMilliseconds: UInt32(stepSeconds * 1000))
    }

    /// A dozen groups, some with many processes, plus hidden processes.
    public static let processes: ProcessSnapshot = {
        var nextPid: Int32 = 400
        func group(
            _ name: String, bundle: String, id: String? = nil, main: String? = nil, helper: String,
            count: Int, cpu: Double, memory: UInt64
        ) -> ProcessGroup {
            let processes = (0..<count).map { index -> ProcessEntry in
                nextPid += 7
                let share = index == 0 ? 0.4 : 0.6 / Double(max(1, count - 1))
                let decay = index == 0 ? 1 : 1 / Double(index)
                let processName = index == 0 ? (main ?? name) : helper
                return ProcessEntry(
                    pid: nextPid, parentPid: index == 0 ? 1 : nextPid - Int32(7 * index), name: processName,
                    path: bundle.isEmpty ? "/usr/bin/\(processName)" : "\(bundle)/Contents/MacOS/\(processName)",
                    cpuPercent: cpu * share * decay, memoryBytes: UInt64(Double(memory) * share * decay),
                    residentBytes: UInt64(Double(memory) * share)
                )
            }
            return ProcessGroup(
                id: id ?? bundle, name: name, bundlePath: bundle,
                cpuPercent: processes.reduce(0) { $0 + $1.cpuPercent },
                memoryBytes: processes.reduce(0) { $0 + $1.memoryBytes }, processes: processes
            )
        }
        let groups = [
            group("Google Chrome", bundle: "/Applications/Google Chrome.app", helper: "Google Chrome Helper (Renderer)", count: 114, cpu: 38.2, memory: 6_890_000_000),
            group("System", bundle: "", id: ProcessGroup.systemID, main: "WindowServer", helper: "launchd", count: 24, cpu: 21.4, memory: 4_700_000_000),
            group("Cursor", bundle: "/Applications/Cursor.app", helper: "Cursor Helper (Plugin)", count: 21, cpu: 12.9, memory: 2_290_000_000),
            group("Spotify", bundle: "/Applications/Spotify.app", helper: "Spotify Helper", count: 6, cpu: 3.1, memory: 475_000_000),
            group("Safari", bundle: "/Applications/Safari.app", helper: "Safari Web Content", count: 10, cpu: 2.4, memory: 223_000_000),
            group("OneMenu", bundle: "/Applications/OneMenu.app", helper: "OneMenu", count: 1, cpu: 0.4, memory: 141_000_000),
            group("Docker", bundle: "/Applications/Docker.app", helper: "com.docker.backend", count: 2, cpu: 1.8, memory: 95_000_000),
            group("1Password", bundle: "/Applications/1Password.app", helper: "1Password Helper", count: 6, cpu: 0.6, memory: 90_500_000),
            group("Rex Beta", bundle: "/Applications/Rex Beta.app", helper: "rex", count: 3, cpu: 4.7, memory: 82_200_000),
            group("node", bundle: "", id: "pid:8812", helper: "node", count: 4, cpu: 9.8, memory: 79_900_000),
            group("Ghostty", bundle: "/Applications/Ghostty.app", helper: "zsh", count: 5, cpu: 1.2, memory: 66_000_000),
            group("Finder", bundle: "/System/Library/CoreServices/Finder.app", helper: "Finder", count: 1, cpu: 0.2, memory: 61_300_000),
        ]
        return ProcessSnapshot(
            time: now, groups: groups,
            hidden: HiddenProcesses(processCount: 312),
            processCount: groups.reduce(312) { $0 + $1.processes.count }
        )
    }()

}

private let gibibyte: UInt64 = 1 << 30
