import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section(String(localized: "Color scheme")) {
                Picker(String(localized: "Mode"), selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(String(localized: "Accent color")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 14) {
                    ForEach(AccentColorChoice.allCases) { choice in
                        AccentColorButton(
                            choice: choice,
                            isSelected: settings.accentColorChoice == choice
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                settings.accentColorChoice = choice
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section(String(localized: "Live preview")) {
                HStack(spacing: 16) {
                    Button(String(localized: "Active Button")) {}
                        .buttonStyle(.borderedProminent)
                        .tint(settings.accentColorChoice.color)

                    Toggle(String(localized: "Sample Switch"), isOn: .constant(true))
                        .tint(settings.accentColorChoice.color)

                    Label(String(localized: "Connected"), systemImage: "bolt.horizontal.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundStyle(settings.accentColorChoice.color)
                        .background(settings.accentColorChoice.color.opacity(0.12), in: Capsule())
                }
                .padding(.vertical, 6)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccentColorButton: View {
    let choice: AccentColorChoice
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 28, height: 28)
                        .shadow(color: isSelected ? choice.color.opacity(0.4) : .clear, radius: 4, y: 1)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(isSelected ? 0.2 : (isHovered ? 0.1 : 0.0)), lineWidth: 2)
                        .padding(-3)
                )

                Text(choice.label)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .quaternaryLabelColor).opacity(0.4) : (isHovered ? Color(nsColor: .quaternaryLabelColor).opacity(0.2) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .accessibilityLabel(choice.label)
    }
}
