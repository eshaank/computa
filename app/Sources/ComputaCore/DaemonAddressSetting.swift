import Foundation
import os

/// The daemon address the app connects to, kept in `UserDefaults`.
public struct DaemonAddressSetting {
    public static let key = "daemonAddress"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "app.computa.Computa", category: "settings")

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The stored address, or the local daemon when none is stored. A stored value that does
    /// not parse is logged and the local daemon is used.
    public var endpoint: DaemonEndpoint {
        guard let text = defaults.string(forKey: Self.key) else { return .local }
        do {
            return try DaemonEndpoint(parsing: text)
        } catch {
            logger.error("stored daemon address \"\(text, privacy: .public)\" is invalid: \(error.description, privacy: .public)")
            return .local
        }
    }

    /// Checks and stores an address typed by the user.
    ///
    /// - Returns: The parsed address.
    /// - Throws: `DaemonEndpointError` when the text is not `host:port`; nothing is stored then.
    @discardableResult
    public func save(_ text: String) throws(DaemonEndpointError) -> DaemonEndpoint {
        let endpoint = try DaemonEndpoint(parsing: text.trimmingCharacters(in: .whitespaces))
        defaults.set(endpoint.description, forKey: Self.key)
        return endpoint
    }
}
