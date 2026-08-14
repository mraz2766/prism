import SwiftUI

struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SettingsViewModel.self) private var viewModel

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                HStack(spacing: 12) {
                    Image("PrismLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Prism")
                        .font(.headline)
                }
                .padding(.vertical, 2)
            }

            Section {
                Toggle(String(localized: "Launch at login"), isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                if let error = viewModel.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
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
            }

            Section {
                LabeledContent(String(localized: "Real-time exit detection")) {
                    Text(String(localized: "Adaptive"))
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(String(localized: "Prism checks once per second while stable and briefly switches to 250 ms confirmation after a possible change."))
            }

            Section {
                Toggle(String(localized: "Notify when the network exit changes"), isOn: Binding(
                    get: { settings.changeNotificationsEnabled },
                    set: { enabled in Task { await viewModel.setNotificationsEnabled(enabled) } }
                ))
            } footer: {
                Text(String(localized: "Notifications are off by default and never appear for the first detection."))
            }
        }
        .formStyle(.grouped)
        .onAppear { viewModel.synchronizeLaunchAtLogin() }
    }
}
