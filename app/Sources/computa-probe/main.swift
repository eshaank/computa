// Phase 0 trial client. Prints ticks streamed by a running computad.
//
// Usage: computa-probe [host:port] [count]

import ComputaCore
import Foundation

let defaultCount = 10

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("computa-probe: \(message)\n".utf8))
    exit(1)
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

print("Connecting to computad at \(endpoint), reading \(count) ticks...")
do {
    let received = try await DaemonClient(endpoint: endpoint).watchTicks(limit: count) { tick in
        let value = tick.value.formatted(.number.precision(.fractionLength(2)))
        print("tick \(tick.sequence)  value \(value)  at \(tick.date.formatted(.iso8601))")
    }
    guard received == count else {
        fail("the daemon ended the stream after \(received) of \(count) ticks")
    }
    print("OK: received \(received) ticks.")
} catch {
    fail("could not read ticks from \(endpoint): \(error)")
}
