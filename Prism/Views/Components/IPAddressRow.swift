import AppKit
import SwiftUI

struct IPAddressRow: View {
    let label: String
    let address: String?
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(address ?? String(localized: "Unavailable"))
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .foregroundStyle(address == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(address == nil)
            .help(String(localized: "Copy IP address"))
            .accessibilityLabel(String(localized: "Copy IP address"))
        }
    }

    private func copy() {
        guard let address else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeInOut(duration: 0.15)) { copied = false }
        }
    }
}
