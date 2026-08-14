import SwiftUI

struct SettingsRootView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            MenuBarSettingsView()
                .tabItem { Label(String(localized: "Menu Bar"), systemImage: "menubar.rectangle") }
            AppearanceSettingsView()
                .tabItem { Label(String(localized: "Appearance"), systemImage: "paintbrush.fill") }
            NetworkSettingsView()
                .tabItem { Label(String(localized: "Network"), systemImage: "network") }
            PrivacySettingsView()
                .tabItem { Label(String(localized: "Privacy"), systemImage: "lock.shield") }
        }
        .padding(18)
        .frame(width: 540, height: 460)
        .tint(settings.accentColorChoice.color)
        .accentColor(settings.accentColorChoice.color)
        .id(settings.accentColorChoice)
        .background(SettingsToolbarSynchronizer(choice: settings.accentColorChoice))
    }
}

private struct SettingsToolbarSynchronizer: NSViewRepresentable {
    let choice: AccentColorChoice

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            DynamicAccentColorRuntime.apply(choice: choice)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            DynamicAccentColorRuntime.apply(choice: choice)
        }
    }
}
