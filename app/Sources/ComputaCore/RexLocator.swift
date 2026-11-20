import Foundation

/// Where the `rex` command was found, or why it was not.
public enum RexLookup: Sendable, Equatable {
    case found(path: String, source: Source)
    /// The path set in Preferences is not an executable file. It is not replaced by a search,
    /// so a typo never quietly runs some other `rex`.
    case settingInvalid(path: String)
    case notFound

    public enum Source: Sendable, Equatable {
        /// Set in Preferences.
        case setting
        /// A folder on `PATH`.
        case path
        /// Where Rex installs it, under the home folder.
        case installLocation
    }

    public var path: String? {
        if case .found(let path, _) = self { path } else { nil }
    }

    /// One line for Preferences: which path is in use, or that none was found.
    public var summary: String {
        switch self {
        case .found(let path, let source):
            let place = switch source {
            case .setting: "set here"
            case .path: "found on PATH"
            case .installLocation: "Rex's install location"
            }
            return "Using \(WorkingDirectory.abbreviatingHome(path)) (\(place))."
        case .settingInvalid(let path):
            return "\(path) is not an executable file."
        case .notFound:
            return "No rex command found on PATH or where Rex installs it."
        }
    }

    /// The error for running an action without a usable `rex`, or nil when one was found.
    public var error: RexActionError? {
        switch self {
        case .found: nil
        case .settingInvalid(let path): .rexNotFound("The rex command \(path) is not an executable file.")
        case .notFound: .rexNotFound("The rex command was not found.")
        }
    }
}

/// Finding the `rex` executable. An app started from Finder gets a short `PATH` without Rex's
/// folder, so after `PATH` it looks where Rex installs the command.
public enum RexLocator {
    /// Rex's install location, relative to the home folder. Note the spaces.
    public static let installPath =
        "Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"

    /// - Parameters:
    ///   - setting: The path set in Preferences; empty means search. A leading "~" is the home folder.
    ///   - environment: Supplies `PATH`.
    ///   - isExecutable: Whether a path is an executable file. Only checked, never run.
    public static func locate(
        setting: String, environment: [String: String], home: String, isExecutable: (String) -> Bool
    ) -> RexLookup {
        let setting = setting.trimmingCharacters(in: .whitespaces)
        if !setting.isEmpty {
            let path = expandingHome(setting, home: home)
            return isExecutable(path) ? .found(path: path, source: .setting) : .settingInvalid(path: path)
        }
        let folders = (environment["PATH"] ?? "").split(separator: ":").map(String.init).filter { !$0.isEmpty }
        for folder in folders {
            let candidate = (folder as NSString).appendingPathComponent("rex")
            if isExecutable(candidate) { return .found(path: candidate, source: .path) }
        }
        let installed = (home as NSString).appendingPathComponent(installPath)
        if isExecutable(installed) { return .found(path: installed, source: .installLocation) }
        return .notFound
    }

    /// `locate` with this process's environment and file system.
    public static func locate(setting: String) -> RexLookup {
        locate(
            setting: setting, environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory(),
            isExecutable: { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                    && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
            }
        )
    }

    static func expandingHome(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return (home as NSString).appendingPathComponent(String(path.dropFirst(2))) }
        return path
    }
}

/// The `rex` command path set in Preferences, kept in `UserDefaults`. Empty means find it.
public struct RexCommandSetting: @unchecked Sendable {
    // UserDefaults is thread-safe; it is only not marked Sendable.
    public static let key = "rexCommandPath"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The stored path, or "" when none is stored.
    public var path: String { defaults.string(forKey: Self.key) ?? "" }

    /// Stores a path typed by the user; blank clears it, so the command is found automatically.
    ///
    /// - Returns: The trimmed text that was stored.
    @discardableResult
    public func save(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(trimmed, forKey: Self.key)
        }
        return trimmed
    }

    /// Where the command is now: the stored path, or a search.
    public func lookup() -> RexLookup { RexLocator.locate(setting: path) }
}
