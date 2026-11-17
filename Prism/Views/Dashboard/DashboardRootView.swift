import SwiftUI

struct DashboardRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var navigation = environment.dashboardNavigation
        VStack(spacing: 0) {
            // NSWindowController hosts this view directly; keep navigation in the content
            // instead of depending on SwiftUI Scene toolbar installation.
            HStack(spacing: 12) {
                Picker(String(localized: "View"), selection: $navigation.destination) {
                    Label(String(localized: "Overview"), systemImage: "network").tag(DashboardNavigationModel.Destination.overview)
                    Label(String(localized: "Network Test"), systemImage: "speedometer").tag(DashboardNavigationModel.Destination.networkTest)
                    Label(String(localized: "History"), systemImage: "clock.arrow.circlepath").tag(DashboardNavigationModel.Destination.history)
                    Label(String(localized: "Diagnostics"), systemImage: "stethoscope").tag(DashboardNavigationModel.Destination.diagnostics)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 440)
                Spacer(minLength: 0)
                Button {
                    environment.refreshCoordinator.triggerManual()
                } label: {
                    RefreshGlyph(isActive: environment.networkViewModel.status.isRefreshing)
                }
                .help(String(localized: "Refresh"))
                .accessibilityLabel(String(localized: "Refresh"))
                .keyboardShortcut("r", modifiers: [.command])
                Button {
                    environment.openSettings()
                } label: { Image(systemName: "gearshape") }
                .help(String(localized: "Settings"))
                .accessibilityLabel(String(localized: "Settings"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.bar)
            Divider()
            ZStack {
                switch navigation.destination {
                case .overview:
                    DashboardOverviewView().transition(.opacity)
                case .networkTest:
                    NetworkTestView().transition(.opacity)
                case .history:
                    HistoryView().transition(.opacity)
                case .diagnostics:
                    DiagnosticsView().transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: navigation.destination)
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
        .tint(environment.settings.accentColorChoice.color)
    }
}
