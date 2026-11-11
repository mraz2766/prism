import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings
    @Environment(SettingsViewModel.self) private var viewModel

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(String(localized: "Launch at login"), isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                if let error = viewModel.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(StatusPalette.offline)
                }

                Toggle(String(localized: "Notify when the network exit changes"), isOn: Binding(
                    get: { settings.changeNotificationsEnabled },
                    set: { enabled in Task { await viewModel.setNotificationsEnabled(enabled) } }
                ))

                Picker(String(localized: "Global shortcut"), selection: $settings.globalHotKey) {
                    ForEach(GlobalHotKeyChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .accessibilityIdentifier("settings.general.hotKey")
                if environment.hotKeyUnavailable {
                    Text(String(localized: "This shortcut is already in use by the system or another app."))
                        .font(.caption)
                        .foregroundStyle(StatusPalette.offline)
                }
            } header: {
                Text(String(localized: "System integration"))
            } footer: {
                Text(String(localized: "Notifications cover exit changes, domestic fallback, and recovery. The global shortcut opens or closes the menu bar panel from any app."))
            }

            Section {
                HStack(spacing: 8) {
                    Text(String(localized: "Detection sensitivity"))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 16)

                    Image(systemName: "leaf")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Slider(
                        value: Binding(
                            get: { Double(settings.detectionSensitivity.rawValue) },
                            set: { value in
                                let rawValue = Int(value.rounded())
                                settings.detectionSensitivity = DetectionSensitivity(rawValue: rawValue) ?? .responsive
                            }
                        ),
                        in: Double(DetectionSensitivity.energySaver.rawValue)...Double(DetectionSensitivity.maximum.rawValue),
                        step: 1
                    )
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: 280)
                    .accessibilityLabel(String(localized: "Detection sensitivity"))
                    .accessibilityValue(settings.detectionSensitivity.label)

                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(settings.detectionSensitivity.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 56, alignment: .trailing)
                }

                Toggle(String(localized: "Periodic metadata verification"), isOn: Binding(
                    get: { settings.automaticRefreshEnabled },
                    set: { settings.automaticRefreshEnabled = $0 }
                ))
                if settings.automaticRefreshEnabled {
                    Picker(String(localized: "Verification interval"), selection: $settings.refreshInterval) {
                        ForEach(RefreshInterval.allCases.filter { $0 != .networkChangesOnly }) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                }
            } header: {
                Text(String(localized: "Refresh & Detection"))
            } footer: {
                Text(String(localized: "Higher sensitivity notices VPN outages, recovery, and region changes sooner, but makes more network requests and uses more energy."))
            }

            Section {
                Toggle(String(localized: "Alert when the exit leaves expected regions"), isOn: Binding(
                    get: { settings.regionGuardEnabled },
                    set: { enabled in Task { await viewModel.setRegionGuardEnabled(enabled) } }
                ))
                .accessibilityIdentifier("settings.general.regionGuard")
                if settings.regionGuardEnabled {
                    LabeledContent(String(localized: "Expected regions")) {
                        TextField(
                            String(localized: "Expected regions"),
                            text: $settings.regionGuardCountries,
                            prompt: Text(verbatim: "JP, US")
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(maxWidth: 220)
                        .accessibilityIdentifier("settings.general.regionGuard.countries")
                    }
                    regionGuardSummary
                }
            } header: {
                Text(String(localized: "Region guard"))
            } footer: {
                Text(String(localized: "Enter two-letter country codes separated by commas. Prism notifies you once and marks the menu bar when the confirmed exit is in any other country."))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { viewModel.synchronizeLaunchAtLogin() }
    }

    @ViewBuilder
    private var regionGuardSummary: some View {
        let codes = settings.regionGuard.expectedCodes
        if codes.isEmpty {
            Text(String(localized: "No valid country code yet. The guard stays inactive."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                ForEach(codes, id: \.self) { code in
                    HStack(spacing: 4) {
                        CountryFlagView(
                            countryCode: code,
                            style: settings.countryFlagStyle,
                            diameter: 14,
                            containerSize: CGSize(width: 18, height: 16)
                        )
                        Text(Locale.autoupdatingCurrent.localizedString(forRegionCode: code) ?? code)
                            .font(.caption)
                    }
                }
                Spacer()
                if environment.isOutsideExpectedRegion {
                    Label(String(localized: "Outside expected region"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(StatusPalette.offline)
                }
            }
        }
    }
}
