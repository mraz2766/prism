import SwiftUI

struct SectionCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat

    init(
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
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
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .separatorColor).opacity(accessibilityContrast == .increased ? 1 : 0),
                        lineWidth: 1
                    )
            )
    }
}
