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
                HStack(spacing: 14) {
                    ForEach(AccentColorChoice.allCases) { choice in
                        CompactAccentColorDot(
                            choice: choice,
                            isSelected: settings.accentColorChoice == choice
                        ) {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                                settings.accentColorChoice = choice
                            }
                        }
                    }
                    Spacer()
                    Text(settings.accentColorChoice.label)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }

            Section(String(localized: "Live preview")) {
                HStack(spacing: 14) {
                    Button(String(localized: "Action")) {}
                        .buttonStyle(.borderedProminent)
                        .tint(settings.accentColorChoice.color)

                    Toggle(String(localized: "Option"), isOn: .constant(true))
                        .tint(settings.accentColorChoice.color)

                    Spacer()

                    Label(String(localized: "Active"), systemImage: "bolt.horizontal.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .foregroundStyle(settings.accentColorChoice.color)
                        .background(settings.accentColorChoice.color.opacity(0.12), in: Capsule())
                }
                .padding(.vertical, 3)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CompactAccentColorDot: View {
    let choice: AccentColorChoice
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(choice.color)
                    .frame(width: 22, height: 22)
                    .shadow(color: isSelected ? choice.color.opacity(0.4) : .clear, radius: 3, y: 1)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.35 : (isHovered ? 0.15 : 0.05)), lineWidth: 1.5)
                    .padding(-3)
            )
            .scaleEffect(isHovered && !isSelected ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .help(choice.label)
        .accessibilityLabel(choice.label)
    }
}
