import SwiftUI

/// The "Search process" field in its own capsule, as in the reference.
struct SearchField: View {
    @Binding var text: String
    var prompt = "Search process"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dimText)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.dimText))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .focusEffectDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.dimText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: DashboardMetrics.searchHeight)
        .background(OutlinedCapsule(fill: Theme.panel))
    }
}
