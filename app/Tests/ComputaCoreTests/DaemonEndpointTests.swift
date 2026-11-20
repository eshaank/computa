import Testing

@testable import ComputaCore

@Suite struct DaemonEndpointTests {
    @Test func parsesHostAndPort() throws {
        let endpoint = try DaemonEndpoint(parsing: "127.0.0.1:7300")
        #expect(endpoint == DaemonEndpoint(host: "127.0.0.1", port: 7300))
        #expect(endpoint.description == "127.0.0.1:7300")
    }

    @Test func localEndpointIsLoopbackOnTheDefaultPort() {
        #expect(DaemonEndpoint.local == DaemonEndpoint(host: "127.0.0.1", port: 7300))
    }

    @Test func rejectsTextWithoutAPort() {
        #expect(throws: DaemonEndpointError.missingPort("localhost")) {
            try DaemonEndpoint(parsing: "localhost")
        }
    }

    @Test func rejectsTextWithoutAHost() {
        #expect(throws: DaemonEndpointError.missingHost(":7300")) {
            try DaemonEndpoint(parsing: ":7300")
        }
    }

    @Test(arguments: ["0", "65536", "-1", "abc", ""])
    func rejectsPortsOutsideTheValidRange(port: String) {
        #expect(throws: DaemonEndpointError.invalidPort(port)) {
            try DaemonEndpoint(parsing: "localhost:\(port)")
        }
    }
}
