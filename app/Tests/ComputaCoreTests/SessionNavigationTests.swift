import Foundation
import Testing

@testable import ComputaCore

@Suite struct SessionNavigationTests {
    let sessions = Fixtures.sessions.sessions
    var computa: RexSession { sessions[1] }

    @Test func nothingOpenIsTheOverview() {
        #expect(SessionNavigation.place(open: [], in: sessions) == .overview)
    }

    @Test func opensASessionThenAPane() throws {
        let path = SessionNavigation.path(to: computa)
        #expect(SessionNavigation.place(open: path, in: sessions) == .session(computa))

        let pane = computa.tabs[1].panes[1]
        let deeper = SessionNavigation.path(to: pane, in: computa)
        #expect(SessionNavigation.place(open: deeper, in: sessions) == .pane(pane, tab: computa.tabs[1], session: computa))
    }

    @Test func survivesARefreshWithNewNumbersAndANewOrder() {
        let pane = computa.tabs[0].panes[0]
        let open = SessionNavigation.path(to: pane, in: computa)
        var refreshed = sessions
        refreshed[1].cpuPercent += 40
        refreshed[1].tabs[0].panes[0].cpuPercent += 40
        refreshed.reverse()
        let place = SessionNavigation.place(open: open, in: refreshed)
        guard case .pane(let shown, _, let session) = place else {
            Issue.record("expected the pane, got \(place)")
            return
        }
        #expect(shown.id == pane.id)
        #expect(shown.cpuPercent == pane.cpuPercent + 40)
        #expect(session.id == computa.id)
    }

    @Test func aClosedPaneFallsBackToItsSession() {
        let open = SessionNavigation.path(to: computa.tabs[0].panes[1], in: computa)
        var refreshed = sessions
        refreshed[1].tabs[0].panes.remove(at: 1)
        #expect(SessionNavigation.place(open: open, in: refreshed) == .session(refreshed[1]))
    }

    @Test func aClosedSessionFallsBackToTheOverview() {
        let open = SessionNavigation.path(to: computa.tabs[0].panes[0], in: computa)
        var refreshed = sessions
        refreshed.remove(at: 1)
        #expect(SessionNavigation.place(open: open, in: refreshed) == .overview)
        #expect(SessionNavigation.place(open: open, in: []) == .overview)
    }

    @Test func aPaneIdWithoutItsSessionOpensNothing() {
        #expect(SessionNavigation.place(open: [computa.tabs[0].panes[0].id], in: sessions) == .overview)
    }

    @Test func backGoesUpOneLevel() {
        let pane = computa.tabs[0].panes[0]
        #expect(SessionNavigation.back(from: .pane(pane, tab: computa.tabs[0], session: computa)) == [computa.id])
        #expect(SessionNavigation.back(from: .session(computa)).isEmpty)
        #expect(SessionNavigation.back(from: .overview).isEmpty)
    }

    @Test func groupsPanesByTabOnlyWhenThereAreSeveral() {
        let single = SessionNavigation.groups(sessions[0])
        #expect(single.count == 1)
        #expect(single[0].tab == nil)
        #expect(single[0].panes.map(\.id) == sessions[0].panes.map(\.id))

        let several = SessionNavigation.groups(computa)
        #expect(several.map(\.tab?.label) == ["app", "daemon"])
        #expect(several.map(\.id) == computa.tabs.map(\.id))
        #expect(several.flatMap(\.panes).map(\.id) == computa.panes.map(\.id))
    }

    @Test func emptyTabsAreLeftOutOfTheGroups() {
        var session = computa
        session.tabs[1].panes = []
        #expect(SessionNavigation.groups(session).map(\.id) == [session.tabs[0].id])
    }
}
