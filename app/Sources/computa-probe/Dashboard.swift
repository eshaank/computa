import ComputaCore
import Foundation
import Synchronization

/// Calls what the dashboard uses: GetHistory for each range, the first process snapshot, then
/// the first sessions snapshot.
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
    do {
        let first = Mutex<ProcessSnapshot?>(nil)
        try await client.watchProcesses(intervalMilliseconds: ProcessStore.intervalMilliseconds) { snapshot in
            first.withLock { $0 = snapshot }
            return false
        }
        if let snapshot = first.withLock({ $0 }) {
            let top = ProcessList.sorted(snapshot.groups, by: .memory).prefix(5)
                .map { "\($0.name) \($0.badge ?? "") \(Format.memory($0.residentBytes)) in RAM, \(Format.memory($0.memoryBytes)) total" }
            print("processes: \(snapshot.groups.count) groups, \(snapshot.processCount) processes; top: \(top.joined(separator: ", "))")
        } else {
            allPassed = false
            print("processes: the stream ended before the first snapshot")
        }
    } catch {
        allPassed = false
        report("processes", error, endpoint)
    }
    if !(await probeSessions(client, endpoint: endpoint)) { allPassed = false }
    return allPassed
}

private func report(_ what: String, _ error: any Error, _ endpoint: DaemonEndpoint) {
    let problem = DaemonProblem(error: error, endpoint: endpoint)
    print("\(what): FAILED, kind \(problem.kind): \(problem.summary) (\(problem.detail))")
}
