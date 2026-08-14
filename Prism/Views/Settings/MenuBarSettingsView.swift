import SwiftUI

struct MenuBarSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section(String(localized: "Display style")) {
                Picker(String(localized: "Menu bar shows"), selection: $settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                if settings.menuBarDisplayMode == .custom {
                    TextField(String(localized: "Custom template"), text: $settings.customMenuTemplate)
                    Text("{flag}  {country}  {code}  {city}  {status}")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Section(String(localized: "Preview")) {
                VStack(spacing: 10) {
                    previewRow(String(localized: "Online"), status: .online(.preview))
                    previewRow(
                        String(localized: "Confirming"),
                        status: .verifying(previous: .preview, candidateAddress: "198.51.100.8")
                    )
                    previewRow(String(localized: "Offline"), status: .offline(previous: .preview))
                }
                .padding(.vertical, 10)
            }
        }
        .formStyle(.grouped)
    }

    private func previewRow(_ label: String, status: NetworkStatus) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(preview(status: status))
                .font(.system(size: NSFont.menuBarFont(ofSize: 0).pointSize))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func preview(status: NetworkStatus) -> String {
        MenuBarLabelRenderer.render(
            status: status,
            mode: settings.menuBarDisplayMode,
            customTemplate: settings.customMenuTemplate
        )
    }
}
