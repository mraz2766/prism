import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section(String(localized: "Appearance")) {
                Picker(String(localized: "Color scheme"), selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            Section(String(localized: "Accent color")) {
                LabeledContent(String(localized: "Prism Blue")) {
                    Circle()
                        .fill(Color(red: 0.259, green: 0.522, blue: 0.957))
                        .frame(width: 18, height: 18)
                        .accessibilityLabel(String(localized: "Blue"))
                }
            }
        }
        .formStyle(.grouped)
    }
}
