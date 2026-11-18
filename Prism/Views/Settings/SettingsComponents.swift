import AppKit
import SwiftUI

// MARK: - 页面与分组

/// 设置页容器：统一边距与分组间距，点击空白处收起输入焦点。
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { SettingsFocus.clear() }
        )
    }
}

enum SettingsFocus {
    /// 让当前窗口放弃文字输入焦点，避免输入框一直闪烁光标。
    @MainActor
    static func clear() {
        guard let window = NSApp.keyWindow, window.firstResponder is NSText else { return }
        window.makeFirstResponder(nil)
    }
}

/// 一组设置：带彩色小图标的标题、圆角卡片和可选脚注。
struct SettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    var footer: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                SettingsGlyph(systemImage: systemImage)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 2)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                content
            }
            .background(SettingsCardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct SettingsCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var cornerRadius: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.7 : 1))
            .overlay(
                shape.strokeBorder(
                    Color(nsColor: .separatorColor).opacity(contrast == .increased ? 1 : 0.55),
                    lineWidth: 0.5
                )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.035), radius: 2, y: 1)
    }
}

/// 分组标题前的小方块图标，颜色跟随强调色。
struct SettingsGlyph: View {
    let systemImage: String
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 一行设置：左侧标题与说明，右侧控件；悬停时整行轻微高亮。
struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let accessory: Accessory
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 38)
        .background(Color.primary.opacity(isHovered ? 0.03 : 0))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 12)
    }
}

/// 开关：统一使用小号系统开关。
struct SettingsSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }
}

/// 行内展开的内容统一使用的过渡：从上方轻推入并淡入。
extension AnyTransition {
    static var settingsReveal: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        )
    }
}

// MARK: - 档位条

/// 五档信号格：点击任一格直接切换档位，填充随档位弹性变化。
struct SettingsLevelMeter: View {
    let levels: Int
    @Binding var level: Int
    let label: String
    let accessibilityTitle: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredLevel: Int?

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<levels, id: \.self) { index in
                    let filled = index <= level
                    let preview = hoveredLevel.map { index <= $0 } ?? false
                    Capsule()
                        .fill(filled ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(preview ? 0.22 : 0.12)))
                        .frame(width: 5, height: 7 + CGFloat(index) * 3.2)
                        .scaleEffect(y: filled && !reduceMotion ? 1 : 0.92, anchor: .bottom)
                        .contentShape(Rectangle().inset(by: -2))
                        .onTapGesture {
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.4)) { level = index }
                        }
                        .onHover { hovering in hoveredLevel = hovering ? index : nil }
                }
            }
            .frame(height: 20, alignment: .bottom)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .frame(width: 52, alignment: .trailing)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.4), value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(label)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: level = min(levels - 1, level + 1)
            case .decrement: level = max(0, level - 1)
            @unknown default: break
            }
        }
    }
}

// MARK: - 流式排布

/// 按行换行排布标签，可左对齐或右对齐。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, max(width, 0)) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var x = alignment == .trailing ? bounds.maxX - row.width : bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - 抖动

/// 输入无效时左右轻抖一下。
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 5
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 4), y: 0))
    }
}
