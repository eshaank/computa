import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2

/// What the app needs from a computad daemon. The app talks to it through this protocol so
/// tests can use a fake.
public protocol MonitorClient: Sendable {
    /// Facts about the machine the daemon runs on.
    func host() async throws -> HostInfo

    /// Streams system samples, calling `onSample` for each one.
    ///
    /// Returns when the daemon ends the stream or `onSample` returns `false`. Cancelling the
    /// calling task ends the stream too.
    ///
    /// - Parameter intervalMilliseconds: Time between samples. Zero means the daemon's own.
    /// - Throws: The error that ended the stream, if it did not end normally.
    func watchSystem(
        intervalMilliseconds: UInt32,
        onSample: @escaping @Sendable (SystemSample) async -> Bool
    ) async throws

    /// Stored samples, oldest first.
    func history(windowSeconds: UInt32, maxPoints: UInt32) async throws -> HistorySeries

    /// Streams the grouped process list, calling `onSnapshot` for each snapshot. Ends like
    /// `watchSystem`.
    ///
    /// - Parameter intervalMilliseconds: Time between snapshots. Zero means 2000.
    /// - Throws: The error that ended the stream, if it did not end normally.
    func watchProcesses(
        intervalMilliseconds: UInt32,
        onSnapshot: @escaping @Sendable (ProcessSnapshot) async -> Bool
    ) async throws

    /// Streams Rex's sessions with their usage, calling `onSnapshot` for each snapshot. Ends like
    /// `watchSystem`. Rex being unreachable is reported inside the snapshots, not as an error.
    ///
    /// - Parameter intervalMilliseconds: Time between snapshots. Zero means 2000.
    /// - Throws: The error that ended the stream, if it did not end normally.
    func watchSessions(
        intervalMilliseconds: UInt32,
        onSnapshot: @escaping @Sendable (SessionsSnapshot) async -> Bool
    ) async throws

    /// An app's icon as PNG data, at most 128 pixels on a side. Empty when the daemon has no
    /// icon for the bundle.
    ///
    /// - Parameter bundlePath: A bundle on the daemon's machine, ending in ".app".
    func appIcon(bundlePath: String) async throws -> Data
}

/// Makes a client for an address. The store makes a fresh one per connection attempt, so a
/// changed address or a restarted daemon is picked up without old connection state.
public typealias MonitorClientFactory = @Sendable (DaemonEndpoint) -> any MonitorClient

/// Calls a computad daemon over gRPC.
public struct DaemonClient: MonitorClient {
    public let endpoint: DaemonEndpoint

    public init(endpoint: DaemonEndpoint = .local) {
        self.endpoint = endpoint
    }

    /// - Throws: The gRPC error if the daemon cannot be reached or the call fails.
    public func host() async throws -> HostInfo {
        let message = try await withMonitor { monitor in
            try await monitor.getHost(Computa_V1_GetHostRequest())
        }
        return HostInfo(message)
    }

    /// - Throws: The gRPC error if the daemon cannot be reached or the stream fails.
    public func watchSystem(
        intervalMilliseconds: UInt32,
        onSample: @escaping @Sendable (SystemSample) async -> Bool
    ) async throws {
        let request = Computa_V1_WatchSystemRequest.with { $0.intervalMs = intervalMilliseconds }
        try await withMonitor { monitor in
            try await monitor.watchSystem(request) { response in
                for try await message in response.messages {
                    guard await onSample(SystemSample(message)) else { break }
                }
            }
        }
    }

    /// - Throws: The gRPC error if the daemon cannot be reached or the call fails.
    public func history(windowSeconds: UInt32, maxPoints: UInt32) async throws -> HistorySeries {
        let request = Computa_V1_GetHistoryRequest.with {
            $0.windowSeconds = windowSeconds
            $0.maxPoints = maxPoints
        }
        let message = try await withMonitor { monitor in
            try await monitor.getHistory(request)
        }
        return HistorySeries(message)
    }

    /// - Throws: The gRPC error if the daemon cannot be reached, does not offer the call, or the
    ///   stream fails.
    public func watchProcesses(
        intervalMilliseconds: UInt32,
        onSnapshot: @escaping @Sendable (ProcessSnapshot) async -> Bool
    ) async throws {
        let request = Computa_V1_WatchProcessesRequest.with { $0.intervalMs = intervalMilliseconds }
        try await withMonitor { monitor in
            try await monitor.watchProcesses(request) { response in
                for try await message in response.messages {
                    guard await onSnapshot(ProcessSnapshot(message)) else { break }
                }
            }
        }
    }

    /// - Throws: The gRPC error if the daemon cannot be reached, does not offer the call, or the
    ///   stream fails.
    public func watchSessions(
        intervalMilliseconds: UInt32,
        onSnapshot: @escaping @Sendable (SessionsSnapshot) async -> Bool
    ) async throws {
        let request = Computa_V1_WatchSessionsRequest.with { $0.intervalMs = intervalMilliseconds }
        try await withMonitor { monitor in
            try await monitor.watchSessions(request) { response in
                for try await message in response.messages {
                    guard await onSnapshot(SessionsSnapshot(message)) else { break }
                }
            }
        }
    }

    /// - Throws: The gRPC error if the daemon cannot be reached, does not offer the call, or
    ///   rejects the path.
    public func appIcon(bundlePath: String) async throws -> Data {
        let request = Computa_V1_GetAppIconRequest.with { $0.bundlePath = bundlePath }
        let message = try await withMonitor { monitor in
            try await monitor.getAppIcon(request)
        }
        return message.png
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
