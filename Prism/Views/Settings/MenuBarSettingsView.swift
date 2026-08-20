import SwiftUI

struct MenuBarSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    private let availableTokens = [
        ("{flag}", "🇨🇳"),
        ("{country}", "China"),
        ("{code}", "CN"),
        ("{city}", "Shanghai"),
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
                .accessibilityIdentifier("settings.menuBar.displayMode")

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

            Section(String(localized: "Country flag style")) {
                Picker(String(localized: "Country flag style"), selection: $settings.countryFlagStyle) {
                    ForEach(CountryFlagStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("settings.menuBar.flagStyle")

                Text(String(localized: "Flag style also applies to the popover, details, and history. Sticker style uses a compact circle flag in the menu bar."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .scrollContentBackground(.hidden)
    }

    private func simulatedMenuBar(_ stateLabel: String, status: NetworkStatus) -> some View {
        let presentation = preview(status: status)
        return HStack(spacing: 12) {
            Text(stateLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    previewIndicator(presentation.indicator)
                    if !presentation.title.isEmpty {
                        Text(presentation.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.menuBar.preview")

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

    private func preview(status: NetworkStatus) -> MenuBarPresentation {
        MenuBarLabelRenderer.presentation(
            status: status,
            mode: settings.menuBarDisplayMode,
            flagStyle: settings.countryFlagStyle,
            customTemplate: settings.customMenuTemplate
        )
    }

    @ViewBuilder
    private func previewIndicator(_ indicator: MenuBarIndicator) -> some View {
        switch indicator {
        case .none:
            EmptyView()
        case .flag(let countryCode):
            CountryFlagView(
                countryCode: countryCode,
                style: settings.countryFlagStyle,
                diameter: 16,
                containerSize: CGSize(width: 18, height: 18)
            )
        case .emoji(let countryCode):
            Text(CountryFlag.emoji(for: countryCode) ?? "◎")
                .font(.system(size: 14))
                .frame(width: 20, height: 18)
        case .systemSymbol(let name):
            Image(systemName: name)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16, height: 16)
        }
    }
}
