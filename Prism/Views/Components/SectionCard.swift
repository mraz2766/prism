import SwiftUI

struct SectionCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let accent: Color?

    /// `accent` 不为空时卡片带一层强调色底色与描边，用于突出主出口。
    init(
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 16,
        accent: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.accent = accent
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.055 : 0.035))
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill((accent ?? .clear).opacity(colorScheme == .dark ? 0.14 : 0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder((accent ?? .clear).opacity(0.28), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .separatorColor).opacity(accessibilityContrast == .increased ? 1 : 0),
                        lineWidth: 1
                    )
            )
    }
}
