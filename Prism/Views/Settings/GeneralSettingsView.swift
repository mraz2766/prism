import SwiftUI

struct GeneralSettingsView: View {
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
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                Toggle(String(localized: "Notify when the network exit changes"), isOn: Binding(
                    get: { settings.changeNotificationsEnabled },
                    set: { enabled in Task { await viewModel.setNotificationsEnabled(enabled) } }
                ))
            } header: {
                Text(String(localized: "System integration"))
            } footer: {
                Text(String(localized: "Notifications are off by default and never appear for the first detection."))
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "Detection sensitivity"))
                        Spacer()
                        Text(settings.detectionSensitivity.label)
                            .foregroundStyle(.secondary)
                    }

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
                    ) {
                        Text(String(localized: "Detection sensitivity"))
                    } minimumValueLabel: {
                        Image(systemName: "leaf")
                    } maximumValueLabel: {
                        Image(systemName: "bolt.fill")
                    }
                    .accessibilityValue(settings.detectionSensitivity.label)
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
                HStack(spacing: 12) {
                    Image("PrismLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text("Prism")
                                .font(.callout.weight(.semibold))
                            Text("v\(appVersion)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Text(String(localized: "Native macOS Network Exit & GeoIP Monitor"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { viewModel.synchronizeLaunchAtLogin() }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
