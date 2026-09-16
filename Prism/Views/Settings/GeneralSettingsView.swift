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
