import SwiftUI

struct SectionCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .background(
                Group {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.regularMaterial)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        .separator.opacity(accessibilityContrast == .increased ? 1 : 0.5),
                        lineWidth: accessibilityContrast == .increased ? 1 : 0.5
                    )
            )
    }
}
