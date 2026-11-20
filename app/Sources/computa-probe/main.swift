// Prints what a running computad reports, for checking its numbers by eye
// against Activity Monitor.
//
// Usage: computa-probe [host:port] [count] [--dashboard]
//
// With --dashboard it also calls GetHistory and WatchProcesses, as the dashboard does.

import ComputaCore
import Foundation
import Synchronization

let defaultCount = 10

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("computa-probe: \(message)\n".utf8))
    exit(1)
}

func line(for sample: SystemSample) -> String {
    let memory = sample.memory
    let disk = sample.startupVolume
    return [
        "cpu \(Format.percent(sample.cpu.usagePercent))",
        "mem \(Format.percent(memory.usedPercent)) (\(Format.memory(memory.usedBytes)) of \(Format.memory(memory.totalBytes)))",
        "swap \(Format.memory(memory.swapUsedBytes))",
        "disk \(disk.map { "\(Format.percent($0.usedPercent)) (\(Format.storage($0.usedBytes)) of \(Format.storage($0.totalBytes)))" } ?? "?")",
        "io r \(Format.rate(sample.diskReadBytesPerSecond)) w \(Format.rate(sample.diskWriteBytesPerSecond))",
        "net down \(Format.rate(sample.network.receiveBytesPerSecond)) up \(Format.rate(sample.network.sendBytesPerSecond))",
        sample.battery.map { "battery \(Format.battery($0))" } ?? "no battery",
    ].joined(separator: " | ")
}

let dashboard = CommandLine.arguments.contains("--dashboard")
let arguments = Array(CommandLine.arguments.dropFirst().filter { $0 != "--dashboard" })
let endpoint: DaemonEndpoint
do {
    endpoint = try arguments.first.map { try DaemonEndpoint(parsing: $0) } ?? .local
} catch {
    fail("bad address: \(error)")
}
guard let count = arguments.count > 1 ? Int(arguments[1]) : defaultCount, count > 0 else {
    fail("count must be a whole number above zero, got \"\(arguments[1])\"")
}

let client = DaemonClient(endpoint: endpoint)
do {
    let host = try await client.host()
    let cores = host.coreGroups.map { "\($0.coreCount) \($0.name)" }.joined(separator: " + ")
    print("\(host.hostname): \(host.chip), \(cores) cores, \(Format.memory(host.memoryTotalBytes)), \(host.osVersion)")
    print("computad \(host.daemonVersion), sampling every \(host.sampleIntervalMilliseconds) ms\n")

    let received = Mutex(0)
    try await client.watchSystem(intervalMilliseconds: 0) { sample in
        print(line(for: sample))
        return received.withLock { total in
            total += 1
            return total < count
        }
    }
    let total = received.withLock { $0 }
    guard total == count else {
        fail("the daemon ended the stream after \(total) of \(count) samples")
    }
    print("\nOK: received \(total) samples.")
    if dashboard, !(await probeDashboard(client, endpoint: endpoint)) {
        fail("some dashboard calls failed")
    }
} catch {
    fail("could not read from \(endpoint): \(DaemonProblem(error: error, endpoint: endpoint).summary) (\(error))")
}
