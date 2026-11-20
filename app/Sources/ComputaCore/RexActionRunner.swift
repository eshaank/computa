import Foundation
import os

/// Runs Rex actions. The app uses `ProcessRexRunner`; tests use a fake.
public protocol RexActionRunning: Sendable {
    func run(_ action: RexAction) async throws(RexActionError) -> RexActionResult
}

/// Runs an action with the `rex` command: `rex [prefix] do -s <session> <action> … --json`.
public struct ProcessRexRunner: RexActionRunning {
    public static let defaultTimeout: Duration = .seconds(10)

    private let locate: @Sendable () -> RexLookup
    private let prefix: [String]
    private let timeout: Duration
    private let logger = Logger(subsystem: "app.computa.Computa", category: "rex")

    /// - Parameters:
    ///   - locate: Finds the `rex` executable, asked again for every action so a new setting
    ///     takes effect at once.
    ///   - prefix: Global options before `do`; see `RexCommandLine.arguments(for:prefix:)`.
    ///   - timeout: After this the child is stopped and the action reports `timedOut`.
    public init(
        locate: @escaping @Sendable () -> RexLookup, prefix: [String] = [], timeout: Duration = defaultTimeout
    ) {
        self.locate = locate
        self.prefix = prefix
        self.timeout = timeout
    }

    public func run(_ action: RexAction) async throws(RexActionError) -> RexActionResult {
        let lookup = locate()
        guard let executable = lookup.path else {
            let error = lookup.error ?? .rexNotFound("The rex command was not found.")
            logger.error("\(action.name, privacy: .public): \(error.description, privacy: .public)")
            throw error
        }
        let arguments = RexCommandLine.arguments(for: action, prefix: prefix)
        logger.info("running \(executable, privacy: .public) \(arguments.joined(separator: " "), privacy: .public)")
        let output: RexProcessOutput
        do {
            output = try await ChildProcess.run(executable: executable, arguments: arguments, timeout: timeout)
        } catch {
            logger.error("\(action.name, privacy: .public): \(error.description, privacy: .public)")
            throw error
        }
        do {
            return try RexOutput.parse(action, output)
        } catch {
            let stderr = String(decoding: output.stderr, as: UTF8.self)
            logger.error(
                "\(action.name, privacy: .public) failed (status \(output.status)): \(error.description, privacy: .public); stderr: \(stderr, privacy: .public)"
            )
            throw error
        }
    }
}
