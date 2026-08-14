import SwiftUI

struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SettingsViewModel.self) private var viewModel

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                HStack(spacing: 14) {
                    Image("PrismLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Prism")
                                .font(.headline.weight(.bold))
                            Text("v2.4.0")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(nsColor: .quaternaryLabelColor), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                        Text(String(localized: "Native macOS Network Exit & GeoIP Monitor"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

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
                LabeledContent(String(localized: "Real-time exit detection")) {
                    Text(String(localized: "Adaptive (1s / 250ms)"))
                        .foregroundStyle(.secondary)
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
                Text(String(localized: "Prism checks once per second while stable and briefly switches to 250 ms confirmation after a possible change."))
            }
        }
        .formStyle(.grouped)
        .onAppear { viewModel.synchronizeLaunchAtLogin() }
    }
}
