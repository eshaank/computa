import GRPCCore

/// Why the app has no live numbers from the daemon, in words for the popover.
public struct DaemonProblem: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Nothing answered at the address.
        case unreachable
        /// The daemon answered but does not offer the call (an older or unfinished daemon).
        case unsupported
        /// The daemon closed the stream.
        case streamEnded
        case other
    }

    public var kind: Kind
    /// One short sentence.
    public var summary: String
    /// The underlying error, for the curious.
    public var detail: String

    public init(kind: Kind, summary: String, detail: String) {
        self.kind = kind
        self.summary = summary
        self.detail = detail
    }

    /// Describes an error from a call to the daemon at `endpoint`.
    public init(error: any Error, endpoint: DaemonEndpoint) {
        guard let rpcError = error as? RPCError else {
            self.init(kind: .other, summary: "Lost contact with computad at \(endpoint).", detail: "\(error)")
            return
        }
        let detail = "\(rpcError.code): \(rpcError.message)"
        switch rpcError.code {
        case .unavailable, .deadlineExceeded:
            self.init(kind: .unreachable, summary: "computad is not running at \(endpoint).", detail: detail)
        case .unimplemented:
            self.init(
                kind: .unsupported,
                summary: "computad at \(endpoint) does not offer this call yet. Update the daemon.",
                detail: detail
            )
        default:
            self.init(kind: .other, summary: "computad at \(endpoint) reported an error.", detail: detail)
        }
    }

    /// The daemon ended the sample stream without an error.
    public static func streamEnded(_ endpoint: DaemonEndpoint) -> DaemonProblem {
        DaemonProblem(
            kind: .streamEnded,
            summary: "computad at \(endpoint) stopped sending samples.",
            detail: "The stream ended without an error."
        )
    }
}

/// Where the app stands with the daemon.
public enum ConnectionState: Sendable, Equatable {
    /// Trying to reach the daemon; no sample yet.
    case connecting
    /// Samples are arriving.
    case connected
    /// The last attempt failed. The store retries by itself.
    case daemonNotRunning(DaemonProblem)

    public var isConnected: Bool { self == .connected }
}
