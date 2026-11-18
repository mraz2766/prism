import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings
    @Environment(SettingsViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reveal: Animation? { reduceMotion ? nil : .smooth(duration: 0.28) }

    var body: some View {
        @Bindable var settings = settings
        SettingsPage {
            SettingsGroup(
                title: String(localized: "System integration"),
                systemImage: "gearshape.2",
                footer: String(localized: "Notifications cover exit changes, domestic fallback, and recovery. The global shortcut opens or closes the menu bar panel from any app.")
            ) {
                SettingsRow(title: String(localized: "Launch at login")) {
                    SettingsSwitch(title: String(localized: "Launch at login"), isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { viewModel.setLaunchAtLogin($0) }
                    ))
                }
                if let error = viewModel.launchAtLoginError {
                    message(error)
                }
                SettingsDivider()
                SettingsRow(title: String(localized: "Notify when the network exit changes")) {
                    SettingsSwitch(title: String(localized: "Notify when the network exit changes"), isOn: Binding(
                        get: { settings.changeNotificationsEnabled },
                        set: { enabled in Task { await viewModel.setNotificationsEnabled(enabled) } }
                    ))
                }
                SettingsDivider()
                SettingsRow(title: String(localized: "Global shortcut")) {
                    Picker(String(localized: "Global shortcut"), selection: $settings.globalHotKey) {
                        ForEach(GlobalHotKeyChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityIdentifier("settings.general.hotKey")
                }
                if environment.hotKeyUnavailable {
                    message(String(localized: "This shortcut is already in use by the system or another app."))
                }
            }

            SettingsGroup(
                title: String(localized: "Refresh & Detection"),
                systemImage: "waveform.path.ecg",
                footer: String(localized: "Higher sensitivity notices VPN outages, recovery, and region changes sooner, but makes more network requests and uses more energy.")
            ) {
                SettingsRow(title: String(localized: "Detection sensitivity")) {
                    SettingsLevelMeter(
                        levels: DetectionSensitivity.allCases.count,
                        level: Binding(
                            get: { settings.detectionSensitivity.rawValue },
                            set: { settings.detectionSensitivity = DetectionSensitivity(rawValue: $0) ?? .responsive }
                        ),
                        label: settings.detectionSensitivity.label,
                        accessibilityTitle: String(localized: "Detection sensitivity")
                    )
                }
                SettingsDivider()
                SettingsRow(title: String(localized: "Periodic metadata verification")) {
                    SettingsSwitch(title: String(localized: "Periodic metadata verification"), isOn: Binding(
                        get: { settings.automaticRefreshEnabled },
                        set: { enabled in withAnimation(reveal) { settings.automaticRefreshEnabled = enabled } }
                    ))
                }
                if settings.automaticRefreshEnabled {
                    VStack(spacing: 0) {
                        SettingsDivider()
                        SettingsRow(title: String(localized: "Verification interval")) {
                            Picker(String(localized: "Verification interval"), selection: $settings.refreshInterval) {
                                ForEach(RefreshInterval.allCases.filter { $0 != .networkChangesOnly }) { interval in
                                    Text(interval.label).tag(interval)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                    }
                    .transition(.settingsReveal)
                }
            }

            SettingsGroup(
                title: String(localized: "Region guard"),
                systemImage: "shield.lefthalf.filled",
                footer: String(localized: "Enter two-letter country codes separated by commas. Prism notifies you once and marks the menu bar when the confirmed exit is in any other country.")
            ) {
                SettingsRow(title: String(localized: "Alert when the exit leaves expected regions")) {
                    HStack(spacing: 10) {
                        if settings.regionGuardEnabled, environment.isOutsideExpectedRegion {
                            Label(String(localized: "Outside expected region"), systemImage: "exclamationmark.triangle.fill")
                                .tagCapsule(StatusPalette.offline)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                        SettingsSwitch(title: String(localized: "Alert when the exit leaves expected regions"), isOn: Binding(
                            get: { settings.regionGuardEnabled },
                            set: { enabled in
                                withAnimation(reveal) { settings.regionGuardEnabled = enabled }
                                Task { await viewModel.setRegionGuardEnabled(enabled) }
                            }
                        ))
                        .accessibilityIdentifier("settings.general.regionGuard")
                    }
                    .animation(reveal, value: environment.isOutsideExpectedRegion)
                }
                if settings.regionGuardEnabled {
                    VStack(spacing: 0) {
                        SettingsDivider()
                        RegionCodeField(
                            storage: $settings.regionGuardCountries,
                            flagStyle: settings.countryFlagStyle
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                    .transition(.settingsReveal)
                }
            }
        }
        .onAppear { viewModel.synchronizeLaunchAtLogin() }
    }

    private func message(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(StatusPalette.offline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }
}
