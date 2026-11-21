import Foundation

/// What `rex` printed and how it exited.
public struct RexProcessOutput: Sendable, Equatable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data

    public init(status: Int32, stdout: Data, stderr: Data) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Reading `rex do … --json`. Pure functions, so they are testable.
///
/// On success `rex` prints the action's result as JSON and exits 0. On failure it prints a line
/// starting "Error: " on stderr and exits non-zero.
public enum RexOutput {
    /// The marker Rex uses when it does not know an action.
    static let unknownAction = "no action named"

    public static func parse(_ action: RexAction, _ output: RexProcessOutput) throws(RexActionError) -> RexActionResult {
        guard output.status == 0 else { throw error(output) }
        let object = try jsonObject(output.stdout)
        switch action {
        case .openProcessViewer:
            guard let program = object["program"] as? String, !program.isEmpty else {
                throw .malformedOutput("no \"program\" in \(preview(output.stdout))")
            }
            return .openedProcessViewer(program: program, windowID: object["window_id"] as? String ?? "")
        case .closePane(let sessionID, _):
            guard let closed = object["closed"] as? String, !closed.isEmpty else {
                throw .malformedOutput("no \"closed\" in \(preview(output.stdout))")
            }
            return .closedPane(paneID: closed, sessionID: object["session_id"] as? String ?? sessionID)
        }
    }

    /// The error for a non-zero exit, from the stderr line that starts "Error: ".
    static func error(_ output: RexProcessOutput) -> RexActionError {
        let text = String(decoding: output.stderr, as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let message = lines.first { $0.hasPrefix("Error: ") }.map { String($0.dropFirst("Error: ".count)) }
        if let message {
            return message.hasPrefix(unknownAction) ? .actionsNotInstalled : .failed(message)
        }
        if let last = lines.last(where: { !$0.isEmpty }) {
            return .failed("rex exited with status \(output.status): \(last)")
        }
        return .failed("rex exited with status \(output.status) and gave no reason")
    }

    private static func jsonObject(_ data: Data) throws(RexActionError) -> [String: Any] {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw .malformedOutput("not JSON: \(preview(data))")
        }
        guard let object = parsed as? [String: Any] else {
            throw .malformedOutput("not a JSON object: \(preview(data))")
        }
        return object
    }

    /// The start of the output, for error messages. "nothing" when empty.
    private static func preview(_ data: Data) -> String {
        let text = String(decoding: data.prefix(80), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "nothing" : "\"\(text)\""
    }
}
