import ComputaCore
import SwiftUI

/// The one setting: which daemon to connect to.
public struct PreferencesView: View {
    @State private var text: String
    @State private var message: String?
    @State private var isError = false
    let save: @MainActor (String) throws(DaemonEndpointError) -> DaemonEndpoint

    /// - Parameters:
    ///   - current: The address in use.
    ///   - save: Checks, stores and applies an address; throws when it is not `host:port`.
    public init(current: DaemonEndpoint, save: @escaping @MainActor (String) throws(DaemonEndpointError) -> DaemonEndpoint) {
        _text = State(initialValue: current.description)
        self.save = save
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daemon address")
                .font(.rowLabel)
                .foregroundStyle(Theme.text)
            HStack(spacing: 8) {
                TextField("127.0.0.1:7300", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13).monospaced())
                    .onSubmit(apply)
                Button("Save", action: apply)
                    .keyboardShortcut(.defaultAction)
            }
            Text(message ?? "host:port of a computad daemon. The default is \(DaemonEndpoint.local).")
                .font(.system(size: 11))
                .foregroundStyle(isError ? Theme.warning : Theme.dimText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 360)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    private func apply() {
        do throws(DaemonEndpointError) {
            let endpoint = try save(text)
            text = endpoint.description
            message = "Saved. Connecting to \(endpoint)."
            isError = false
        } catch {
            message = error.description
            isError = true
        }
    }
}
