import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            MenuBarSettingsView()
                .tabItem { Label(String(localized: "Menu Bar"), systemImage: "menubar.rectangle") }
            AppearanceSettingsView()
                .tabItem { Label(String(localized: "Appearance"), systemImage: "circle.lefthalf.filled") }
            NetworkSettingsView()
                .tabItem { Label(String(localized: "Network"), systemImage: "network") }
            PrivacySettingsView()
                .tabItem { Label(String(localized: "Privacy"), systemImage: "hand.raised") }
        }
        .padding(18)
        .frame(width: 540, height: 440)
    }
}
