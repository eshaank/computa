import ComputaCore
import Foundation
import Synchronization

/// Calls what the dashboard uses: GetHistory for each range, the first process snapshot, the
/// first snapshot with traffic rates, then the first sessions snapshot.
/// Each failure is printed with the problem the dashboard would show, and the probe goes on.
func probeDashboard(_ client: DaemonClient, endpoint: DaemonEndpoint) async -> Bool {
    var allPassed = true
    for range in HistoryRange.allCases {
        do {
            let history = try await client.history(windowSeconds: range.windowSeconds, maxPoints: HistoryStore.maxPoints)
            let newest = history.points.last.map { "newest cpu \(Format.percent($0.cpuUsagePercent)), mem \(Format.memory($0.memoryUsedBytes))" } ?? "no points"
            print("history \(range.title): \(history.points.count) points, step \(history.stepMilliseconds) ms, \(newest)")
        } catch {
            allPassed = false
            report("history \(range.title)", error, endpoint)
        }
    }
    if !(await probeProcesses(client, endpoint: endpoint)) { allPassed = false }
    if !(await probeTraffic(client, endpoint: endpoint)) { allPassed = false }
    if !(await probeSessions(client, endpoint: endpoint)) { allPassed = false }
    return allPassed
}

/// The first process snapshot: the top five by memory in RAM, with all three memory figures.
private func probeProcesses(_ client: DaemonClient, endpoint: DaemonEndpoint) async -> Bool {
    do {
        guard let snapshot = try await snapshots(client, count: 1, traffic: false).first else {
            print("processes: the stream ended before the first snapshot")
            return false
        }
        let reported = snapshot.reportsResidentSize
        let top = ProcessList.sorted(snapshot.groups, by: .memory, residentReported: reported).prefix(5).map { group in
            let figures = MemoryFigures(group, residentReported: reported)
            return "\(group.name) \(group.badge ?? "") mem \(figures.mem), compressed+swap ~\(figures.compressedOrSwapped), footprint \(figures.footprint)"
        }
        print("processes: \(snapshot.groups.count) groups, \(snapshot.processCount) processes; top: \(top.joined(separator: "; "))")
        return true
    } catch {
        report("processes", error, endpoint)
        return false
    }
}

/// A stream that asks for traffic, read until the daemon stops saying "measuring": its first
/// snapshots have no rates yet. Gives up after `trafficPatience` snapshots.
private func probeTraffic(_ client: DaemonClient, endpoint: DaemonEndpoint) async -> Bool {
    do {
        let received = try await snapshots(client, count: trafficPatience, traffic: true) {
            TrafficAvailability($0.network) != .measuring
        }
        guard let snapshot = received.last else {
            print("traffic: the stream ended before the first snapshot")
            return false
        }
        switch TrafficAvailability(snapshot.network) {
        case .daemonNeedsUpdate:
            print("traffic: the daemon sent no network status; it needs an update")
        case .measuring:
            print("traffic: still measuring after \(received.count) snapshots")
        case .problem(let problem):
            print("traffic: not available: \(problem)")
        case .available:
            let top = ProcessList.sorted(snapshot.groups, by: .network).prefix(5).map { group in
                let figures = TrafficFigures(group)
                return "\(group.name) down \(figures.down) up \(figures.up)"
            }
            print("traffic: \(top.joined(separator: "; "))")
        }
        return true
    } catch {
        report("traffic", error, endpoint)
        return false
    }
}

/// How many snapshots the traffic check waits for rates: about twelve seconds.
private let trafficPatience = 6

/// The first `count` snapshots of a process stream, or fewer when `isEnough` accepts one sooner.
private func snapshots(
    _ client: DaemonClient, count: Int, traffic: Bool,
    stopWhen isEnough: @escaping @Sendable (ProcessSnapshot) -> Bool = { _ in false }
) async throws -> [ProcessSnapshot] {
    let received = Mutex<[ProcessSnapshot]>([])
    try await client.watchProcesses(intervalMilliseconds: ProcessStore.intervalMilliseconds, includeNetwork: traffic) { snapshot in
        received.withLock { $0.append(snapshot) }
        return received.withLock { $0.count } < count && !isEnough(snapshot)
    }
    return received.withLock { $0 }
}

private func report(_ what: String, _ error: any Error, _ endpoint: DaemonEndpoint) {
    let problem = DaemonProblem(error: error, endpoint: endpoint)
    print("\(what): FAILED, kind \(problem.kind): \(problem.summary) (\(problem.detail))")
}
