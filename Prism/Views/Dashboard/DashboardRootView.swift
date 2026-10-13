import SwiftUI

struct DashboardRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var navigation = environment.dashboardNavigation
        ZStack {
            switch navigation.destination {
            case .overview:
                DashboardOverviewView()
                    .transition(.opacity)
            case .history:
                HistoryView()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: navigation.destination)
        .frame(minWidth: 640, minHeight: 460)
        .tint(environment.settings.accentColorChoice.color)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(String(localized: "View"), selection: $navigation.destination) {
                    Label(String(localized: "Overview"), systemImage: "network").tag(DashboardNavigationModel.Destination.overview)
                    Label(String(localized: "History"), systemImage: "clock.arrow.circlepath").tag(DashboardNavigationModel.Destination.history)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            ToolbarItemGroup {
                Button {
                    environment.refreshCoordinator.triggerManual()
                } label: { Image(systemName: "arrow.clockwise") }
                    .help(String(localized: "Refresh"))
                    .keyboardShortcut("r", modifiers: [.command])
                Button {
                    environment.openSettingsAction?()
                } label: { Image(systemName: "gearshape") }
                    .help(String(localized: "Settings"))
            }
        }
    }
}
