import Foundation
import ImageIO
import Testing

@testable import ComputaCore

/// The closest this Mac gets to "gRPC streams correctly through the tunnel": the real
/// supervisor runs a stand-in `ssh` that forwards the `-L` port to a real phase 6 daemon, and
/// the app's real stores and gRPC client talk to it through that port. Only ssh itself is
/// replaced.
@MainActor
@Suite(.serialized) struct TunnelEndToEndTests {
    @Test func grpcStreamsThroughAForwardedPortAndStoppingTearsItDown() async throws {
        guard FileManager.default.isExecutableFile(atPath: DaemonUnderTest.binary) else {
            print("skipping the end-to-end tunnel test: \(DaemonUnderTest.binary) is missing")
            return
        }
        guard let python = python3Path else {
            print("skipping the end-to-end tunnel test: no python3 for the forwarding stand-in")
            return
        }
        let daemon = try DaemonUnderTest()
        defer { daemon.stop() }
        try await daemon.waitUntilListening()
        let ssh = try StandInSSH(#"exec '\#(python)' "$(dirname "$0")/forward.py" "$@""#)
        defer { ssh.remove() }
        try forwarderScript.write(to: ssh.folder.appendingPathComponent("forward.py"), atomically: true, encoding: .utf8)

        let (controller, stores, m1) = try setUp(daemonPort: daemon.port, ssh: ssh.executable.path)
        defer {
            controller.stop()
            stores.monitor.stop()
            stores.history.setOpen(false)
        }
        stores.monitor.setOpen(true, .popover)
        stores.history.setOpen(true)
        stores.monitor.start()
        controller.select(m1)

        try await waitUntil("tunnel connected") { controller.tunnelState?.endpoint != nil }
        let tunnelEnd = try #require(controller.tunnelState?.endpoint)
        #expect(tunnelEnd.port != daemon.port, "the app talks to the forward, not the daemon")
        #expect(stores.monitor.endpoint == tunnelEnd)
        #expect(try ssh.arguments().contains("127.0.0.1:\(tunnelEnd.port):127.0.0.1:\(daemon.port)"))

        try await waitUntil("GetHost through the tunnel") { stores.monitor.host != nil }
        #expect(stores.monitor.host?.daemonVersion.isEmpty == false)
        let seen = SampleTimes()
        try await waitUntil("two samples through the tunnel") {
            if let sample = stores.monitor.sample { seen.times.insert(sample.time) }
            return seen.times.count >= 2
        }
        try await waitUntil("history through the tunnel") { stores.history.series != nil }

        try await expectCalculatorIcon(machineID: m1, through: tunnelEnd)

        try await expectTeardown(controller, ssh: ssh, tunnelEnd: tunnelEnd)
    }

    /// Switching back to This Mac stops the stand-in ssh and frees the tunnel's port.
    private func expectTeardown(_ controller: MachineController, ssh: StandInSSH, tunnelEnd: DaemonEndpoint) async throws {
        let forwarder = try #require(ssh.pid())
        #expect(processExists(forwarder))
        controller.select(Machine.thisMacID)
        #expect(controller.tunnelState == nil)
        try await waitUntil("forwarder pid \(forwarder) gone", timeout: .seconds(5)) { !processExists(forwarder) }
        #expect(!LocalPort.accepts(tunnelEnd.port), "nothing listens on the tunnel's port any more")
        #expect(ssh.launchCount == 1, "one ssh for the whole session")
    }

    /// One real GetAppIcon through the tunnel: a PNG that decodes, at most 128 pixels.
    private func expectCalculatorIcon(machineID: String, through endpoint: DaemonEndpoint) async throws {
        let icons = RemoteIconCache()
        let entry = await icons.load(.init(machineID: machineID, bundlePath: "/System/Applications/Calculator.app"), endpoint: endpoint)
        guard case .png(let png) = entry else {
            Issue.record("expected a PNG for Calculator, got \(String(describing: entry))")
            return
        }
        let image = try #require(CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(image.width > 0 && image.width <= 128 && image.height <= 128)
    }

    /// This Mac points at a port nothing listens on, so the test never touches 7300.
    private func setUp(daemonPort: Int, ssh: String) throws -> (MachineController, MachineStores, String) {
        let name = "computa-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        var list = MachineList(thisMacAddress: DaemonEndpoint(host: "127.0.0.1", port: try LocalPort.free()))
        let m1 = try list.add(MachineDraft(name: "M1", destination: "tester@m1", daemonPort: String(daemonPort)))
        try MachineSettings(defaults: defaults).save(list)
        let stores = MachineStores(
            monitor: MonitorStore(endpoint: .local), history: HistoryStore(endpoint: .local),
            processes: ProcessStore(endpoint: .local), sessions: SessionStore(endpoint: .local)
        )
        let controller = MachineController(settings: MachineSettings(defaults: defaults), stores: stores) {
            SSHTunnel(machine: $0, executable: ssh)
        }
        return (controller, stores, m1.id)
    }
}

/// Distinct sample times seen. A class, so the polling closure captures no local `var`.
@MainActor
private final class SampleTimes {
    var times: Set<Date> = []
}
