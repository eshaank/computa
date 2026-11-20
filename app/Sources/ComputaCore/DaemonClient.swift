import GRPCCore
import GRPCNIOTransportHTTP2

/// Calls a computad daemon over gRPC.
public struct DaemonClient: Sendable {
    public let endpoint: DaemonEndpoint

    public init(endpoint: DaemonEndpoint = .local) {
        self.endpoint = endpoint
    }

    /// Facts about the machine the daemon runs on.
    ///
    /// - Throws: The gRPC error if the daemon cannot be reached or the call fails.
    package func host() async throws -> Computa_V1_Host {
        try await withMonitor { monitor in
            try await monitor.getHost(Computa_V1_GetHostRequest())
        }
    }

    /// Streams system samples from the daemon, calling `onSample` for each one.
    ///
    /// Returns after `limit` samples, or when the daemon ends the stream.
    ///
    /// - Parameters:
    ///   - intervalMilliseconds: Time between samples. Zero means the daemon's own interval.
    ///   - limit: How many samples to read before stopping.
    /// - Returns: The number of samples received.
    /// - Throws: The gRPC error if the daemon cannot be reached or the stream fails.
    @discardableResult
    package func watchSystem(
        intervalMilliseconds: UInt32 = 0,
        limit: Int,
        onSample: @Sendable @escaping (Computa_V1_SystemSample) -> Void
    ) async throws -> Int {
        let request = Computa_V1_WatchSystemRequest.with {
            $0.intervalMs = intervalMilliseconds
        }
        return try await withMonitor { monitor in
            try await monitor.watchSystem(request) { response in
                var received = 0
                for try await sample in response.messages {
                    onSample(sample)
                    received += 1
                    if received >= limit { break }
                }
                return received
            }
        }
    }

    private func withMonitor<Result: Sendable>(
        _ body: @Sendable @escaping (Computa_V1_Monitor.Client<HTTP2ClientTransport.Posix>) async throws -> Result
    ) async throws -> Result {
        try await withGRPCClient(
            transport: .http2NIOPosix(
                target: .dns(host: endpoint.host, port: endpoint.port),
                transportSecurity: .plaintext
            )
        ) { client in
            try await body(Computa_V1_Monitor.Client(wrapping: client))
        }
    }
}
