/// Where a computad daemon can be reached.
public struct DaemonEndpoint: Sendable, Equatable, CustomStringConvertible {
    public var host: String
    public var port: Int

    /// The daemon on this Mac, on its default port.
    public static let local = DaemonEndpoint(host: "127.0.0.1", port: 7300)

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    /// Parses `host:port`, for example `127.0.0.1:7300`.
    ///
    /// - Throws: `DaemonEndpointError` when the text is not a host and a
    ///   port between 1 and 65535.
    public init(parsing text: String) throws(DaemonEndpointError) {
        guard let colon = text.lastIndex(of: ":") else {
            throw .missingPort(text)
        }
        let host = String(text[..<colon])
        let portText = String(text[text.index(after: colon)...])
        guard !host.isEmpty else {
            throw .missingHost(text)
        }
        guard let port = Int(portText), (1...65535).contains(port) else {
            throw .invalidPort(portText)
        }
        self.init(host: host, port: port)
    }

    public var description: String { "\(host):\(port)" }
}

public enum DaemonEndpointError: Error, Equatable, CustomStringConvertible {
    case missingPort(String)
    case missingHost(String)
    case invalidPort(String)

    public var description: String {
        switch self {
        case .missingPort(let text): "\"\(text)\" has no port; expected host:port"
        case .missingHost(let text): "\"\(text)\" has no host; expected host:port"
        case .invalidPort(let port): "\"\(port)\" is not a port between 1 and 65535"
        }
    }
}
