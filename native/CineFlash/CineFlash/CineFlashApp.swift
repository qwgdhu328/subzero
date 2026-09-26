import SwiftUI

@main
struct CineFlashApp: App {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootGate()
                .environmentObject(app)
                .tint(Theme.accent)
                .onOpenURL { url in
                    // Deep link dall'Isola Dinamica: cineflash://news
                    if url.scheme == "cineflash" && url.host == "news" {
                        app.showNew()
                    }
                }
                .onChange(of: scenePhase) { phase in
                    // Tocco sull'isola porta l'app in primo piano: chiudi la Live Activity
                    if phase == .active && app.newCount > 0 {
                        app.showNew()
                    }
                }
        }
    }
}

/// Gating del primo avvio: onboarding alla prima apertura, poi le tab.
struct RootGate: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if app.settings.onboarded != true {
            OnboardingView()
        } else {
            MainTabs()
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Oggi", systemImage: "newspaper") }
            AITabView()
                .tabItem { Label("AI", systemImage: "sparkles") }
            SettingsTabView()
                .tabItem { Label("Impostazioni", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
    }
}
