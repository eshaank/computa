import Foundation

/// Harder fixtures for the Sessions tab's snapshots: many sessions, long names and paths, a
/// session with three tabs, and the figures an older daemon sends.
extension Fixtures {
    /// Seven sessions, one with three tabs and a name too long for a card.
    public static let sessionsBusy = SessionsSnapshot(
        time: now,
        rex: RexStatus(reachable: true, problem: "", version: "0.1.0-preview.14"),
        sessions: sessions.sessions + [
            SessionBuilder.session("ece118-final-project-with-a-very-long-session-name", id: "session:e118", tabs: [
                SessionBuilder.tab("firmware", id: "window:e118-1", panes: [
                    SessionBuilder.claude("block:e118-a", directory: "/Users/morgan/Documents/school/ece118/ece118-project", memory: 690, cpu: 2.9),
                    SessionBuilder.program("Python", "block:e118-b", directory: "/Users/morgan/Documents/school/ece118/ece118-project/ECE118/ds30Wrapper/build/output", helpers: ["python3.12"], memory: 210, cpu: 1.0),
                ]),
                SessionBuilder.tab("simulation and plotting", id: "window:e118-2", panes: [
                    SessionBuilder.claude("block:e118-c", directory: "/Users/morgan/Documents/school/ece118/ece118-project", memory: 512, cpu: 0.6),
                    SessionBuilder.claude("block:e118-d", directory: "/Users/morgan/Documents/school/ece118/ece118-project/SluggyPotter.X", memory: 488, cpu: 0.3),
                ]),
                SessionBuilder.tab("shell", id: "window:e118-3", panes: [
                    SessionBuilder.shell("block:e118-e", directory: "/Users/morgan/Documents/school/ece118/ece118-project/SluggyPotter.X", memory: 6, cpu: 0),
                ]),
            ]),
            SessionBuilder.session("tellatubbies", id: "session:7e11", tabs: [
                SessionBuilder.tab("tellatubbies", id: "window:7e11-1", panes: [
                    SessionBuilder.claude("block:7e11-a", directory: "/Users/morgan/Projects/tellatubbies", memory: 602, cpu: 1.1),
                    SessionBuilder.claude("block:7e11-b", directory: "/Users/morgan/Projects/tellatubbies/web", memory: 377, cpu: 0.7),
                    SessionBuilder.program("bun", "block:7e11-c", directory: "/Users/morgan/Projects/tellatubbies/web", helpers: ["esbuild"], memory: 188, cpu: 4.2),
                ]),
            ]),
            SessionBuilder.session("notes", id: "session:40de", tabs: [
                SessionBuilder.tab("notes", id: "window:40de-1", panes: [
                    SessionBuilder.program("nvim", "block:40de-a", directory: "/Users/morgan/Notes", helpers: [], memory: 48, cpu: 0.1),
                ]),
            ]),
        ]
    )

    /// `sessions` as a daemon from before resident sizes sends it: every resident size 0, the
    /// processes' too, so only footprints are known.
    public static let sessionsOldDaemon: SessionsSnapshot = {
        var snapshot = sessions
        snapshot.sessions = snapshot.sessions.map(withoutResident)
        return snapshot
    }()

    private static func withoutResident(_ session: RexSession) -> RexSession {
        var session = session
        session.residentBytes = 0
        session.tabs = session.tabs.map { tab in
            var tab = tab
            tab.residentBytes = 0
            tab.panes = tab.panes.map { pane in
                var pane = pane
                pane.residentBytes = 0
                pane.processes = pane.processes.map { process in
                    var process = process
                    process.residentBytes = 0
                    return process
                }
                return pane
            }
            return tab
        }
        return session
    }
}
