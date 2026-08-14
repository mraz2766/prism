import SwiftUI

struct InfoRow: View {
    let label: String
    let value: String
    var icon: String? = nil
    var monospaced = false
    var allowsWrapping = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: icon != nil ? 88 : 96, alignment: .leading)
            Spacer(minLength: 0)
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .monospacedDigit()
                .lineLimit(allowsWrapping ? 2 : 1)
                .truncationMode(.middle)
                .help(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}
