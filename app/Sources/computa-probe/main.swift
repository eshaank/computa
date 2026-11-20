// Prints what a running computad reports, for checking its numbers by eye
// against Activity Monitor.
//
// Usage: computa-probe [host:port] [count]

import ComputaCore
import Foundation

let defaultCount = 10

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("computa-probe: \(message)\n".utf8))
    exit(1)
}

func gigabytes(_ bytes: UInt64) -> String {
    (Double(bytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(2))) + " GB"
}

func megabytesPerSecond(_ bytesPerSecond: Double) -> String {
    (bytesPerSecond / 1_048_576).formatted(.number.precision(.fractionLength(2))) + " MB/s"
}

func percent(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1))) + "%"
}

let arguments = Array(CommandLine.arguments.dropFirst())
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
    print("\(host.hostname): \(host.chip), \(cores) cores, \(gigabytes(host.memoryTotalBytes)), \(host.osVersion)")
    print("computad \(host.daemonVersion), sampling every \(host.sampleIntervalMs) ms\n")

    let received = try await client.watchSystem(limit: count) { sample in
        let memory = sample.memory
        let disk = sample.volumes.first
        let line = [
            "cpu \(percent(sample.cpu.usagePercent))",
            "mem \(gigabytes(memory.usedBytes)) of \(gigabytes(memory.totalBytes))",
            "swap \(gigabytes(memory.swapUsedBytes))",
            "disk \(disk.map { gigabytes($0.usedBytes) } ?? "?") used",
            "io r \(megabytesPerSecond(sample.diskActivity.readBytesPerSec)) w \(megabytesPerSecond(sample.diskActivity.writeBytesPerSec))",
            "net down \(megabytesPerSecond(sample.network.rxBytesPerSec)) up \(megabytesPerSecond(sample.network.txBytesPerSec))",
            sample.hasBattery ? "battery \(percent(sample.battery.chargePercent))" : "no battery",
        ].joined(separator: " | ")
        print(line)
    }
    guard received == count else {
        fail("the daemon ended the stream after \(received) of \(count) samples")
    }
    print("\nOK: received \(received) samples.")
} catch {
    fail("could not read from \(endpoint): \(error)")
}
