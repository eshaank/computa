import ComputaCore
import SwiftUI

/// The "rex command" setting: a path, or empty to find `rex` automatically, and which path is in
/// use or that none was found.
struct RexCommandSection: View {
    @State private var text: String
    @State private var lookup: RexLookup
    let save: @MainActor (String) -> RexLookup

    /// - Parameters:
    ///   - current: The stored path; empty when the command is found automatically.
    ///   - lookup: Where the command is now.
    ///   - save: Stores a path (blank clears it) and returns where the command is then.
    init(current: String, lookup: RexLookup, save: @escaping @MainActor (String) -> RexLookup) {
        _text = State(initialValue: current)
        _lookup = State(initialValue: lookup)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("rex command")
                .font(.rowLabel)
                .foregroundStyle(Theme.text)
            HStack(spacing: 8) {
                TextField("Find automatically", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13).monospaced())
                    .onSubmit(apply)
                Button("Save", action: apply)
            }
            Text(lookup.summary)
                .font(.system(size: 11))
                .foregroundStyle(lookup.path == nil ? Theme.warning : Theme.dimText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text("Runs Computa's Rex actions. Leave empty to search PATH, then where Rex installs it.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func apply() {
        lookup = save(text)
        text = text.trimmingCharacters(in: .whitespaces)
    }
}
