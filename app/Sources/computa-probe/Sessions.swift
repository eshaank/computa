import ComputaCore
import Foundation
import Synchronization

/// Prints the first sessions snapshot: one line per session, its panes indented under it with
/// kind, program, directory and memory. Returns false when the call failed.
func probeSessions(_ client: DaemonClient, endpoint: DaemonEndpoint) async -> Bool {
    do {
        let first = Mutex<SessionsSnapshot?>(nil)
        try await client.watchSessions(intervalMilliseconds: SessionStore.intervalMilliseconds) { snapshot in
            first.withLock { $0 = snapshot }
            return false
        }
        guard let snapshot = first.withLock({ $0 }) else {
            print("sessions: the stream ended before the first snapshot")
            return false
        }
        printSessions(snapshot)
        return true
    } catch {
        let problem = DaemonProblem(error: error, endpoint: endpoint)
        print("sessions: FAILED, kind \(problem.kind): \(problem.summary) (\(problem.detail))")
        return false
    }
}

private func printSessions(_ snapshot: SessionsSnapshot) {
    let rex = snapshot.rex
    guard rex.reachable else {
        print("sessions: Rex unreachable: \(rex.problem.isEmpty ? "(no reason given)" : rex.problem)")
        return
    }
    let summary = SessionsSummary(snapshot.sessions)
    print(
        "sessions: Rex \(rex.version.isEmpty ? "?" : rex.version), \(summary.sessionCount) sessions, "
            + "\(summary.tabCount) tabs, \(summary.paneCount) panes, \(summary.claudePaneCount) Claude "
            + "(\(memoryWords(summary.claudeMemory))); total \(Format.cpuShare(summary.cpuPercent)), "
            + memoryWords(summary.memory)
    )
    for session in SessionList.sorted(snapshot.sessions, by: .memory) {
        print("  \(session.label) [\(session.id)] \(memoryWords(session.memory)), \(Format.cpuShare(session.cpuPercent)), \(session.processCount) processes")
        for tab in session.tabs {
            for pane in tab.panes {
                let directory = pane.workingDirectory.isEmpty ? "?" : WorkingDirectory.display(pane.workingDirectory, maxLength: 60)
                print("    \(tab.label) / \(kindName(pane.kind)) \(pane.title) \(directory) \(memoryWords(pane.memory)), \(pane.processCount) processes")
            }
        }
    }
}

private func kindName(_ kind: PaneKind) -> String {
    switch kind {
    case .claude: "claude"
    case .shell: "shell"
    case .program: "program"
    case .unspecified: "unspecified"
    }
}

/// "1.4 GB in RAM, 2.0 GB footprint", or the footprint alone from a daemon too old to report
/// memory in RAM.
private func memoryWords(_ memory: SessionMemory) -> String {
    guard let resident = memory.resident else { return "\(Format.memory(memory.footprint)) footprint" }
    return "\(Format.memory(resident)) in RAM, \(Format.memory(memory.footprint)) footprint"
}
