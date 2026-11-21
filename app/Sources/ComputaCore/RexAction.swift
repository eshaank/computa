import Foundation

/// A Rex action the app runs with `rex do`. The actions themselves live in `rex/computa.lua`.
///
/// The app runs outside any Rex terminal, so every action names its session.
public enum RexAction: Sendable, Equatable {
    /// `computa_open_top`: opens btop (or top) in a new tab of the session.
    case openProcessViewer(sessionID: String)
    /// `computa_close_pane`: closes one pane and ends the program running in it.
    case closePane(sessionID: String, paneID: String)

    /// The action's name in `rex/computa.lua`.
    public var name: String {
        switch self {
        case .openProcessViewer: "computa_open_top"
        case .closePane: "computa_close_pane"
        }
    }

    public var sessionID: String {
        switch self {
        case .openProcessViewer(let sessionID), .closePane(let sessionID, _): sessionID
        }
    }

    /// What the action works on, so the app never runs two at once for the same thing.
    public var target: RexActionTarget {
        switch self {
        case .openProcessViewer(let sessionID): .session(sessionID)
        case .closePane(_, let paneID): .pane(paneID)
        }
    }
}

/// The session or pane an action works on, by Rex's id.
public enum RexActionTarget: Sendable, Hashable {
    case session(String)
    case pane(String)
}

/// Building the `rex` command line. A pure function, so it is testable.
public enum RexCommandLine {
    /// The arguments after the executable, for example
    /// `["do", "-s", "session:…", "computa_close_pane", "block_id=block:…", "--json"]`.
    ///
    /// - Parameter prefix: Global options that go before `do`. Empty acts on this Mac's Rex
    ///   server; `["-S", host]` acts on another one.
    public static func arguments(for action: RexAction, prefix: [String] = []) -> [String] {
        var arguments = prefix + ["do", "-s", action.sessionID, action.name]
        if case .closePane(_, let paneID) = action {
            // One argument, never split: Rex splits it on the first "=".
            arguments.append("block_id=\(paneID)")
        }
        arguments.append("--json")
        return arguments
    }

    /// The global options that point `rex` at another machine's server.
    public static func hostPrefix(_ host: String) -> [String] { ["-S", host] }
}

/// What a successful action reported.
public enum RexActionResult: Sendable, Equatable {
    /// The full path of the viewer that opened, for example "/opt/homebrew/bin/btop".
    case openedProcessViewer(program: String, windowID: String)
    case closedPane(paneID: String, sessionID: String)

    /// One short sentence for the Sessions tab's outcome line.
    public var summary: String {
        switch self {
        case .openedProcessViewer(let program, _):
            let name = URL(fileURLWithPath: program).lastPathComponent
            return "Opened \(name.isEmpty ? "the process viewer" : name) in a new tab."
        case .closedPane:
            return "Closed the pane."
        }
    }
}

/// Why an action did not run, each with one sentence a person can act on.
public enum RexActionError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Rex does not know the action: `rex/computa.lua` is not installed or not loaded.
    case actionsNotInstalled
    /// No `rex` executable. The text says where the app looked.
    case rexNotFound(String)
    /// `rex` did not finish in time and was stopped.
    case timedOut(Duration)
    /// `rex` or the action failed. The text after "Error: ", or a description of the failure.
    case failed(String)
    /// `rex` said it succeeded but printed something the app cannot read.
    case malformedOutput(String)

    public var description: String {
        switch self {
        case .actionsNotInstalled:
            "Rex actions not installed. Run just install-rex-actions in the Computa folder, then rex config reload."
        case .rexNotFound(let detail):
            "\(detail) Set its path in Preferences."
        case .timedOut(let duration):
            "rex did not answer within \(Self.seconds(duration)) and was stopped. Check that Rex is running."
        case .failed(let message):
            Self.sentence(message)
        case .malformedOutput(let detail):
            "rex gave an answer Computa cannot read (\(detail)). Check that Rex and Computa's actions are up to date."
        }
    }

    private static func seconds(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return seconds == seconds.rounded() ? "\(Int(seconds)) s" : String(format: "%.1f s", seconds)
    }

    /// Capitalised and ending in a full stop.
    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "rex failed and gave no reason." }
        let capitalised = first.uppercased() + trimmed.dropFirst()
        return capitalised.last.map { ".!?".contains($0) } == true ? capitalised : capitalised + "."
    }
}
