import AppKit
import SwiftUI

struct IPAddressRow: View {
    let label: String
    let address: String?
    var detail: String? = nil
    var placeholder: String? = nil
    var accessibilityIdentifier: String? = nil
    @State private var copied = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(label)
                        .font(.caption.weight(.medium))
                    if let detail {
                        Text("· \(detail)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
                if let address {
                    Text(address)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text(placeholder ?? String(localized: "Unavailable"))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Button(action: copy) {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                    if copied {
                        Text(String(localized: "Copied"))
                            .font(.caption2.weight(.medium))
                    }
                }
                .foregroundStyle(copied ? .green : (isHovered ? .primary : .secondary))
                .padding(.horizontal, copied ? 8 : 6)
                .frame(minWidth: 30, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(copied ? Color.green.opacity(0.12) : (isHovered ? Color(nsColor: .quaternaryLabelColor) : Color.clear))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(address == nil)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
            }
            .help(String(localized: "Copy IP address"))
            .accessibilityLabel(String(localized: "Copy IP address"))
        }
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private func copy() {
        guard let address else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }
}
