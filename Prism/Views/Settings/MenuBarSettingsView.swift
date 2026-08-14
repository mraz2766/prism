import SwiftUI

struct MenuBarSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    private let availableTokens = [
        ("{flag}", "🇯🇵"),
        ("{country}", "Japan"),
        ("{code}", "JP"),
        ("{city}", "Tokyo"),
        ("{status}", "●")
    ]

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
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(String(localized: "Custom template"), text: $settings.customMenuTemplate)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 6) {
                            Text(String(localized: "Insert:"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(availableTokens, id: \.0) { token, sample in
                                Button(action: { insertToken(token) }) {
                                    Text("\(token) (\(sample))")
                                        .font(.caption2.monospaced())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color(nsColor: .quaternaryLabelColor), in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                                .help(String(localized: "Click to append to template"))
                            }
                        }
                    }
                }
            }

            Section(String(localized: "Menu Bar Preview")) {
                VStack(spacing: 8) {
                    simulatedMenuBar(String(localized: "Online"), status: .online(.preview))
                    simulatedMenuBar(
                        String(localized: "Confirming"),
                        status: .verifying(previous: .preview, candidateAddress: "198.51.100.8")
                    )
                    simulatedMenuBar(String(localized: "Offline"), status: .offline(previous: .preview))
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    private func simulatedMenuBar(_ stateLabel: String, status: NetworkStatus) -> some View {
        HStack(spacing: 12) {
            Text(stateLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            HStack(spacing: 12) {
                Text(preview(status: status))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Image(systemName: "wifi")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Image(systemName: "controlcenter")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
                    )
            )
        }
    }

    private func insertToken(_ token: String) {
        if settings.customMenuTemplate.isEmpty {
            settings.customMenuTemplate = token
        } else {
            settings.customMenuTemplate += " \(token)"
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
