import SwiftUI

struct DashboardRootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var navigation = environment.dashboardNavigation
        Group {
            switch navigation.destination {
            case .overview:
                DashboardOverviewView()
            case .history:
                HistoryView()
            }
        }
        .frame(minWidth: 640, minHeight: 460)
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
        .tint(Color(red: 0.259, green: 0.522, blue: 0.957))
    }
}
