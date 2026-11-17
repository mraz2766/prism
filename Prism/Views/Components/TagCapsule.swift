import SwiftUI

/// 全局统一的胶囊标签尺寸：状态、路线、代理、越界、熔断等标签共用同一字号和内边距。
enum TagCapsuleMetrics {
    static let font: Font = .caption.weight(.medium)
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 3
    static let backgroundOpacity: Double = 0.13
}

extension View {
    /// 用同一种颜色绘制文字和浅色底。
    func tagCapsule(_ color: Color) -> some View {
        tagCapsule(foreground: color, background: color.opacity(TagCapsuleMetrics.backgroundOpacity))
    }

    func tagCapsule<Foreground: ShapeStyle, Background: ShapeStyle>(
        foreground: Foreground,
        background: Background
    ) -> some View {
        font(TagCapsuleMetrics.font)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, TagCapsuleMetrics.horizontalPadding)
            .padding(.vertical, TagCapsuleMetrics.verticalPadding)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    /// 中性灰色胶囊，用于路线等说明性标签。
    func neutralTagCapsule() -> some View {
        tagCapsule(
            foreground: Color.secondary,
            background: Color(nsColor: .quaternaryLabelColor).opacity(0.4)
        )
    }
}

/// 卡片标题：图标放在固定宽度的槽位里，不同符号的文字起点对齐。
struct CardTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .frame(width: 18, alignment: .center)
            configuration.title
        }
    }
}

extension LabelStyle where Self == CardTitleLabelStyle {
    static var cardTitle: CardTitleLabelStyle { CardTitleLabelStyle() }
}
