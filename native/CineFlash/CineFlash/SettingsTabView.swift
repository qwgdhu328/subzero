import SwiftUI
import UIKit

/// Tab "Impostazioni": tutto il controllo dell'app in una pagina dedicata.
/// Le pagine sono in ordine: Notifiche → Isola Dinamica → Esperienza →
/// Dashboard AI → Privacy → Permessi → Watchlist → Gestione dati.
struct SettingsTabView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        ScreenHeader(
                            eyebrow: "CineFlash · Le tue preferenze",
                            title: "Impostazioni")
                    }
                    .padding(.bottom, 6)

                    Group {
                        // 1. Notifiche
                        settingsCard("Notifiche") {
                            Toggle("Avvisami subito", isOn: Binding(
                                get: { app.settings.notifyEnabled != false },
                                set: { v in app.update { $0.notifyEnabled = v } }))
                                .tint(Theme.accent)
                                .font(Theme.ui(15, .bold))
                            Text("Notifica locale quando arrivano nuove notizie o si aprono prevendite.")
                                .font(Theme.ui(13)).foregroundColor(Theme.textDim)
                        }
                        // 2. Isola Dinamica
                        settingsCard("Isola Dinamica") {
                            Toggle("Mostra notizie e prevendite sull'isola", isOn: Binding(
                                get: { app.settings.liveActivitiesEnabled != false },
                                set: { v in
                                    app.update { $0.liveActivitiesEnabled = v }
                                    if v {
                                        NewsActivityManager.shared.showNews(
                                            emoji: "🎟️",
                                            headline: "CineFlash è pronto",
                                            detail: "Ti avvisiamo qui le novità",
                                            newCount: 0)
                                    } else {
                                        NewsActivityManager.shared.endAll()
                                    }
                                }))
                                .tint(Theme.accent)
                                .font(Theme.ui(15, .bold))
                            Text("Una pillola live sull'Isola Dinamica con l'ultima notizia e il conteggio delle novità, con priorità alle prevendite. Richiede iPhone 14 Pro o successivo.")
                                .font(Theme.ui(13)).foregroundColor(Theme.textDim)
                            GhostButton(label: "⚙ Apri le impostazioni di sistema") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                        // 3. Esperienza
                        settingsCard("L'esperienza") {
                            Text("L'intro al primo avvio racconta come funziona CineFlash: puoi rivederla quando vuoi. 🍿")
                                .font(Theme.ui(13)).foregroundColor(Theme.textDim)
                            GhostButton(label: "🎬 Rivedi l'intro") {
                                app.update { $0.onboarded = false }
                            }
                        }
                        // 4. Dashboard AI
                        NavigationLink(value: DetailRoute.aiDashboard) {
                            settingsCard("Dashboard AI", body: "La redazione AI valuta il catalogo e decide quali film promuovere e quali togliere.")
                        }
                        .buttonStyle(.plain)
                        // 5. Privacy
                        NavigationLink(value: DetailRoute.privacy) {
                            settingsCard("Privacy e dati", body: "Nessun account, nessun analytics, nessun tracker: le tue liste restano solo sul tuo dispositivo.")
                        }
                        .buttonStyle(.plain)
                        // 6. Permessi
                        NavigationLink(value: DetailRoute.permissions) {
                            settingsCard("Permessi", body: "Notifiche, fototeca e posizione: cosa l'app usa e perché.")
                        }
                        .buttonStyle(.plain)
                        // 7. Watchlist
                        settingsCard("I miei film (\(app.watchlist.count))") {
                            if app.watchlist.isEmpty {
                                Text("Aggiungi film alla watchlist dal Catalogo con la stella.")
                                    .font(Theme.ui(13)).foregroundColor(Theme.textDim)
                            } else {
                                Text(app.watchlist.map(\.title).joined(separator: " · "))
                                    .font(Theme.ui(14)).foregroundColor(Theme.text).lineLimit(3)
                                GhostButton(label: "↗ Esporta / condividi la lista") { shareWatchlist() }
                            }
                        }
                        // 8. Gestione dati
                        settingsCard("Gestione dati") {
                            GhostButton(label: "🗑 Svuota notizie salvate (\(app.savedNews.count))") {
                                for e in app.savedNews { _ = app.toggleSaved(e.item) }
                            }
                            GhostButton(label: "🗑 Svuota watchlist (\(app.watchlist.count))") {
                                for e in app.watchlist { _ = app.toggleWatchlist(e) }
                            }
                        }
                    }

                    Text("CineFlash 2.0 · fatta per chi ama il cinema")
                        .font(Theme.ui(11)).foregroundColor(Theme.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }
                .padding(Theme.pad)
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(for: DetailRoute.self) { $0.destination }
    }

    @ViewBuilder
    private func settingsCard(_ title: String, @ViewBuilder body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold)).kerning(1.2)
                .foregroundColor(Theme.textDim)
            body()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func settingsCard(_ title: String, body text: String) -> some View {
        settingsCard(title) { Text(text).font(Theme.ui(13)).foregroundColor(Theme.textDim) }
    }

    private func shareWatchlist() {
        let msg = "I miei film da vedere 🎬\n\n" +
            app.watchlist.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n") +
            "\n\n— condiviso da CineFlash"
        let av = UIActivityViewController(activityItems: [msg], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first?.present(av, animated: true)
    }
}
