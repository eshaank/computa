import GRPCCore
import GRPCNIOTransportHTTP2

/// Calls a computad daemon over gRPC.
public struct DaemonClient: Sendable {
    public let endpoint: DaemonEndpoint

    public init(endpoint: DaemonEndpoint = .local) {
        self.endpoint = endpoint
    }

    /// Streams ticks from the daemon, calling `onTick` for each one.
    ///
    /// Returns after `limit` ticks, or when the daemon ends the stream.
    ///
    /// - Parameters:
    ///   - intervalMilliseconds: Time between ticks. Zero means the daemon's default.
    ///   - limit: How many ticks to read before stopping.
    /// - Returns: The number of ticks received.
    /// - Throws: The gRPC error if the daemon cannot be reached or the stream fails.
    @discardableResult
    public func watchTicks(
        intervalMilliseconds: UInt32 = 0,
        limit: Int,
        onTick: @Sendable @escaping (Tick) -> Void
    ) async throws -> Int {
        let request = Computa_V1_WatchTicksRequest.with {
            $0.intervalMs = intervalMilliseconds
        }
        return try await withGRPCClient(
            transport: .http2NIOPosix(
                target: .dns(host: endpoint.host, port: endpoint.port),
                transportSecurity: .plaintext
            )
        ) { client in
            let monitor = Computa_V1_Monitor.Client(wrapping: client)
            return try await monitor.watchTicks(request) { response in
                var received = 0
                for try await message in response.messages {
                    onTick(Tick(message))
                    received += 1
                    if received >= limit { break }
                }
                return received
            }
        }
    }
}
