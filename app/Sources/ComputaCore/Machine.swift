import Foundation

/// A Mac whose daemon the app can watch: this one, or another reached through an SSH tunnel.
public struct Machine: Sendable, Equatable, Codable, Identifiable {
    /// The id of the machine running the app. Always in the list.
    public static let thisMacID = "this-mac"
    public static let thisMacName = "This Mac"

    public enum Kind: Sendable, Equatable, Codable {
        /// The Mac running the app; its daemon is reached directly at this address.
        case thisMac(address: DaemonEndpoint)
        /// Another Mac, reached through an SSH tunnel.
        case remote(RemoteMachine)
    }

    /// Stable across renames; a UUID for remote machines.
    public var id: String
    public var name: String
    public var kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    public static func thisMac(address: DaemonEndpoint = .local) -> Machine {
        Machine(id: thisMacID, name: thisMacName, kind: .thisMac(address: address))
    }

    public var isThisMac: Bool { id == Self.thisMacID }

    public var remote: RemoteMachine? {
        if case .remote(let remote) = kind { remote } else { nil }
    }

    /// Where the Sessions tab's Rex actions run for this machine.
    public var rexTarget: RexTarget {
        switch kind {
        case .thisMac: .thisMac
        case .remote(let remote): remote.rexHost.map(RexTarget.host) ?? .unavailable
        }
    }
}

/// How to reach another Mac's daemon: `ssh -L <local>:127.0.0.1:<daemonPort> <destination>`.
public struct RemoteMachine: Sendable, Equatable, Codable {
    /// What the owner types after `ssh`, for example `eshaan@100.64.0.5`.
    public var destination: String
    /// `-p`, when not ssh's default.
    public var sshPort: Int?
    /// The port computad listens on, on that Mac's loopback.
    public var daemonPort: Int
    /// What the owner passes to `rex -S`, for the Sessions tab's actions. Nil: no actions.
    public var rexHost: String?

    public static let defaultDaemonPort = 7300

    public init(destination: String, sshPort: Int? = nil, daemonPort: Int = defaultDaemonPort, rexHost: String? = nil) {
        self.destination = destination
        self.sshPort = sshPort
        self.daemonPort = daemonPort
        self.rexHost = rexHost
    }

    /// The host part of the destination, for messages: `100.64.0.5` from `eshaan@100.64.0.5`.
    public var hostName: String {
        destination.split(separator: "@", omittingEmptySubsequences: false).last.map(String.init) ?? destination
    }
}

/// Which Rex server an action goes to. Captured when the action is issued, so a remote
/// session's id never reaches this Mac's Rex.
public enum RexTarget: Sendable, Equatable {
    case thisMac
    /// `rex -S <host>`.
    case host(String)
    /// A remote machine without a Rex host label: no actions.
    case unavailable

    /// The global options before `do`, or nil when actions are unavailable.
    public var prefix: [String]? {
        switch self {
        case .thisMac: []
        case .host(let host): RexCommandLine.hostPrefix(host)
        case .unavailable: nil
        }
    }
}

extension DaemonEndpoint: Codable {
    private enum CodingKeys: String, CodingKey { case host, port }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(host: try container.decode(String.self, forKey: .host), port: try container.decode(Int.self, forKey: .port))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
    }
}
