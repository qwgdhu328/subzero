import SwiftUI

@main
struct CineFlashApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootGate()
                .environmentObject(app)
                .tint(Theme.accent)
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
            CatalogView()
                .tabItem { Label("Catalogo", systemImage: "film") }
            AITabView()
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .tint(Theme.accent)
    }
}
