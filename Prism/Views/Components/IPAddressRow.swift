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
    @State private var resetCopiedTask: Task<Void, Never>?
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
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .help(address)
                } else {
                    Text(placeholder ?? "—")
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
                .foregroundStyle(copied ? AnyShapeStyle(StatusPalette.online) : (isHovered ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)))
                .padding(.horizontal, copied ? 8 : 6)
                .frame(minWidth: 30, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(copied ? StatusPalette.online.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(address == nil)
            .opacity(address == nil ? 0.4 : 1)
            .help(String(localized: "Copy IP address"))
            .accessibilityLabel(String(localized: "Copy IP address"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered && address != nil ? Color.primary.opacity(0.06) : Color.clear)
        )
        .padding(.horizontal, -8)
        .padding(.vertical, -5)
        // 点击整行即可复制，不必瞄准右侧的小按钮。
        .contentShape(Rectangle())
        .onTapGesture(perform: copy)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: address)
        .onDisappear { resetCopiedTask?.cancel() }
    }

    private func copy() {
        guard let address else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { copied = true }
        // 连续复制时取消上一次的复位，避免“已复制”提前消失。
        resetCopiedTask?.cancel()
        resetCopiedTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { copied = false }
        }
    }
}
