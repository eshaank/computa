import ComputaCore
import SwiftUI

/// The "rex command" setting as a form section: a path, or empty to find `rex` automatically,
/// and which path is in use or that none was found.
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
        Section {
            LabeledContent("rex command") {
                HStack(spacing: 8) {
                    TextField("rex command", text: $text, prompt: Text("Find automatically"))
                        .labelsHidden()
                        .onSubmit(apply)
                    Button("Save", action: apply)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("In use")
                Text(lookup.summary)
                    .font(.callout)
                    .foregroundStyle(lookup.path == nil ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Rex")
        } footer: {
            Text("Runs Computa's Rex actions. Leave empty to search PATH, then where Rex installs it.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func apply() {
        lookup = save(text)
        text = text.trimmingCharacters(in: .whitespaces)
    }
}
