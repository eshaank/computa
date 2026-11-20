import Foundation
import GRPCCore
import Testing

@testable import ComputaCore

@Suite struct DaemonAddressSettingTests {
    func freshDefaults() -> UserDefaults {
        let name = "computa-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToTheLocalDaemon() {
        #expect(DaemonAddressSetting(defaults: freshDefaults()).endpoint == .local)
    }

    @Test func savesAValidAddress() throws {
        let setting = DaemonAddressSetting(defaults: freshDefaults())
        try setting.save(" 10.0.0.5:7400 ")
        #expect(setting.endpoint == DaemonEndpoint(host: "10.0.0.5", port: 7400))
    }

    @Test func rejectsAnInvalidAddressAndKeepsTheOldOne() throws {
        let setting = DaemonAddressSetting(defaults: freshDefaults())
        try setting.save("127.0.0.1:7301")
        #expect(throws: DaemonEndpointError.invalidPort("99999")) { try setting.save("host:99999") }
        #expect(setting.endpoint.port == 7301)
    }

    @Test func aCorruptStoredValueFallsBackToLocal() {
        let defaults = freshDefaults()
        defaults.set("nonsense", forKey: DaemonAddressSetting.key)
        #expect(DaemonAddressSetting(defaults: defaults).endpoint == .local)
    }
}

@Suite struct DaemonProblemTests {
    let endpoint = DaemonEndpoint.local

    @Test func unavailableMeansNotRunning() {
        let problem = DaemonProblem(error: RPCError(code: .unavailable, message: "refused"), endpoint: endpoint)
        #expect(problem.kind == .unreachable)
        #expect(problem.summary == "computad is not running at 127.0.0.1:7300.")
    }

    @Test func unimplementedMeansUnsupported() {
        let problem = DaemonProblem(error: RPCError(code: .unimplemented, message: "x"), endpoint: endpoint)
        #expect(problem.kind == .unsupported)
    }

    @Test func otherErrorsKeepTheirDescription() {
        struct Odd: Error {}
        let problem = DaemonProblem(error: Odd(), endpoint: endpoint)
        #expect(problem.kind == .other)
        #expect(problem.detail.contains("Odd"))
    }
}
