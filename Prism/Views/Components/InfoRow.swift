import SwiftUI

struct InfoRow: View {
    let label: String
    let value: String
    var monospaced = false
    var allowsWrapping = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
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
