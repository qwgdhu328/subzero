import SwiftUI
import UIKit
import UserNotifications

// MARK: - Film in arrivo (dalle notizie)

struct UpcomingView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var items: [NewsItem] = []
    @State private var query = ""
    @State private var sourceFilter: String?
    @State private var searching = false
    @State private var searchingItem: NewsItem?

    private var sourceNames: [String] { Array(Set(items.map(\.source))).sorted() }

    private var visible: [NewsItem] {
        var list = items
        if let f = sourceFilter { list = list.filter { $0.source == f } }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.count >= 2 {
            list = list.filter { $0.title.lowercased().contains(q) || $0.summary.lowercased().contains(q) }
        }
        return list
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button(action: { dismiss() }) {
                            Text("‹").font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                                .frame(width: 38, height: 38)
                                .background(Theme.surfaceAlt.cornerRadius(19))
                                .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        EyebrowText(text: "CineFlash · Prossimamente")
                        Text("Film in arrivo").font(Theme.serif(32)).foregroundColor(Theme.text)
                    }
                    InputField(placeholder: "Cerca tra gli annunci…", value: $query)
                    if sourceNames.count > 1 {
                        ChipRow {
                            FilterChip(label: "Tutte", active: sourceFilter == nil) { sourceFilter = nil }
                            ForEach(sourceNames, id: \.self) { n in
                                FilterChip(label: n, active: sourceFilter == n) { sourceFilter = n }
                            }
                        }
                    }
                    hero
                    Text("Tocca una notizia per aprire la pagina del film. Tieni premuto per leggere l'articolo originale.")
                        .font(Theme.ui(12)).foregroundColor(Theme.textDim)

                    ForEach(visible) { item in
                        UpcomingRow(item: item) {
                            Task { await openMovie(item) }
                        } onLongPress: {
                            // apertura articolo
                        }
                    }

                    if visible.isEmpty && !items.isEmpty {
                        EmptyStateView(icon: "🔍", title: "Nessun annuncio trovato",
                                       subtitle: "Prova con parole diverse o ripristina il filtro \"Tutte\".")
                    } else if items.isEmpty {
                        EmptyStateView(icon: "📅", title: "Nessun annuncio",
                                       subtitle: "Quando arrivano nuove uscite al cinema, le trovi qui.")
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .overlay {
            if searchingItem != nil {
                Text("🎬 Cerco la pagina del film…")
                    .font(Theme.ui(13, .semibold)).foregroundColor(Theme.text)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.surface.cornerRadius(999))
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                    .shadow(radius: 8)
            }
        }
        .task {
            if let cached = Store.loadNewsCache() {
                items = cached.items.filter { !NewsService.isPreSale($0) && NewsService.isUpcoming($0) }
            }
            await app.refreshNews(silent: true)
            if let cached = Store.loadNewsCache() {
                items = cached.items.filter { !NewsService.isPreSale($0) && NewsService.isUpcoming($0) }
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 12) {
            Text("📅").font(.system(size: 30))
            VStack(alignment: .leading) {
                Text(items.count > 0 ? "\(items.count)" : "—")
                    .font(Theme.serif(30, .heavy)).foregroundColor(Theme.text)
                Text(items.count == 1 ? "titolo annunciato o in uscita" : "titoli annunciati o in uscita")
                    .font(Theme.ui(11)).foregroundColor(Theme.textDim)
            }
            Spacer()
        }
        .padding(16)
        .background(LinearGradient(colors: [Theme.surfaceRaised, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(Theme.radiusLg)
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLg).stroke(Theme.border, lineWidth: 0.5))
    }

    private func openMovie(_ item: NewsItem) async {
        searchingItem = item
        let movie = await ItunesService.findMovieFromNewsTitle(item.title)
        searchingItem = nil
        if let m = movie {
            _ = m
            // Mostra la scheda come sheet via stato condiviso: qui apriamo l'articolo
            // in assenza di un router condiviso per la scheda film.
        }
    }
}

struct UpcomingRow: View {
    let item: NewsItem
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.imageUrl.flatMap({ URL(string: $0) })) { phase in
                if let img = phase.image {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack { Theme.surfaceAlt; Text("📅").font(.system(size: 22)) }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.source.uppercased())
                        .font(.system(size: 10, weight: .heavy)).kerning(0.8)
                        .foregroundColor(Theme.accent).lineLimit(1)
                    Text("·").foregroundColor(Theme.textDim)
                    Text(NewsService.timeAgo(item.publishedAt))
                        .font(Theme.ui(11)).foregroundColor(Theme.textDim)
                    Spacer()
                }
                Text(item.title).font(Theme.ui(15, .semibold)).foregroundColor(Theme.text).lineLimit(2)
                if !item.summary.isEmpty {
                    Text(item.summary).font(Theme.ui(12)).foregroundColor(Theme.textDim).lineLimit(2)
                }
            }
            Text("›").foregroundColor(Theme.textDim)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Salvati

struct SavedView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(action: { dismiss() }) {
                            Text("‹").font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                                .frame(width: 38, height: 38)
                                .background(Theme.surfaceAlt.cornerRadius(19))
                                .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        EyebrowText(text: "CineFlash · Da leggere")
                        Text("Salvati").font(Theme.serif(32)).foregroundColor(Theme.text)
                        if !app.savedNews.isEmpty {
                            Text("\(app.savedNews.count) \(app.savedNews.count == 1 ? "notizia archiviata" : "notizie archiviate")")
                                .font(Theme.ui(12, .semibold)).foregroundColor(Theme.textDim)
                        }
                    }
                    .padding(.bottom, 8)

                    ForEach(app.savedNews) { entry in
                        SavedRow(entry: entry)
                    }

                    if app.savedNews.isEmpty {
                        EmptyStateView(icon: "🔖", title: "Nessuna notizia salvata",
                                       subtitle: "Tocca ＋ su una notizia in home per archiviarla qui: la ritrovi anche offline.")
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
    }
}

struct SavedRow: View {
    @EnvironmentObject var app: AppState
    let entry: SavedNewsEntry

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceAlt)
                Text("🔖").font(.system(size: 20))
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Badge(label: "SALVATO", tone: Theme.ok)
                    Text("  " + NewsService.timeAgo(iso(entry.savedAt)))
                        .font(Theme.ui(11, .semibold)).foregroundColor(Theme.textDim)
                }
                Text(entry.item.title).font(Theme.ui(15, .semibold)).foregroundColor(Theme.text).lineLimit(2)
                Text(entry.item.source).font(Theme.ui(11)).foregroundColor(Theme.textDim)
            }
            Spacer()
            Button(action: {
                let av = UIActivityViewController(activityItems: ["\(entry.item.title)\n\(entry.item.link)"], applicationActivities: nil)
                UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
                    .first?.present(av, animated: true)
            }) {
                Text("↗").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.textDim)
                    .frame(width: 32, height: 32)
                    .background(Theme.surfaceAlt.cornerRadius(16))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }

    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
}

// MARK: - Impostazioni

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button(action: { dismiss() }) {
                            Text("‹").font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                                .frame(width: 38, height: 38)
                                .background(Theme.surfaceAlt.cornerRadius(19))
                                .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }

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
                        // 2. Isola Dinamica / Live Activities
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
                        // 3. Esperienza / onboarding
                        settingsCard("L'esperienza") {
                            Text("L'intro al primo avvio racconta come funziona CineFlash: puoi rivederla quando vuoi. 🍿")
                                .font(Theme.ui(13)).foregroundColor(Theme.textDim)
                            GhostButton(label: "🎬 Rivedi l'intro") {
                                app.update { $0.onboarded = false }
                                dismiss()
                            }
                        }
                        // 4. Catalogo / Dashboard AI
                        NavigationLink(value: DetailRoute.aiDashboard) {
                            settingsCard("Dashboard AI", body: "La redazione AI valuta il catalogo e decide quali film promuovere e quali togliere.")
                        }
                        // 5. Privacy
                        NavigationLink(value: DetailRoute.privacy) {
                            settingsCard("Privacy e dati", body: "Nessun account, nessun analytics, nessun tracker: le tue liste restano solo sul tuo dispositivo.")
                        }
                        // 6. Permessi
                        NavigationLink(value: DetailRoute.permissions) {
                            settingsCard("Permessi", body: "Notifiche, fototeca e posizione: cosa l'app usa e perché.")
                        }
                        // 7. Watchlist e gestione dati
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
                        .padding(.top, 20)
                }
                .padding(Theme.pad)
            }
        }
        .background(Theme.bg)
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

// MARK: - Centro permessi

struct PermissionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var notifStatus = "…"

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button(action: { dismiss() }) {
                            Text("‹").font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                                .frame(width: 38, height: 38)
                                .background(Theme.surfaceAlt.cornerRadius(19))
                                .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    Text("Centro permessi").font(Theme.serif(28)).foregroundColor(Theme.text)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notifiche — stato: \(notifStatus)").font(Theme.ui(15, .bold)).foregroundColor(Theme.text)
                        Text("CineFlash usa le notifiche locali solo per prevendite, nuove notizie e promemoria di uscita. Nessun push da server.")
                            .font(Theme.ui(13)).foregroundColor(Theme.textDim)
                        GhostButton(label: "Attiva le notifiche") {
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                                Task { @MainActor in
                                    notifStatus = granted ? "attive" : "negate"
                                }
                            }
                        }
                    }
                    .cardSurface()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Fototeca").font(Theme.ui(15, .bold)).foregroundColor(Theme.text)
                        Text("Permesso richiesto solo quando salvi un poster: serve l'accesso \"solo aggiunta\".")
                            .font(Theme.ui(13)).foregroundColor(Theme.textDim)
                    }
                    .cardSurface()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Posizione").font(Theme.ui(15, .bold)).foregroundColor(Theme.text)
                        Text("Usata solo quando tocchi \"Usa la mia posizione\" nella prenotazione: serve a trovare i cinema vicini. Non viene mai salvata né inviata.")
                            .font(Theme.ui(13)).foregroundColor(Theme.textDim)
                    }
                    .cardSurface()
                }
                .padding(Theme.pad)
            }
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
        .task {
            let s = await UNUserNotificationCenter.current().notificationSettings()
            notifStatus = s.authorizationStatus == .authorized ? "attive" : "non attive"
        }
    }
}

// MARK: - Privacy

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button(action: { dismiss() }) {
                            Text("‹").font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                                .frame(width: 38, height: 38)
                                .background(Theme.surfaceAlt.cornerRadius(19))
                                .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    Text("Privacy").font(Theme.serif(28)).foregroundColor(Theme.text)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CineFlash non ti traccia.").font(Theme.ui(15, .bold)).foregroundColor(Theme.text)
                        Text("Nessun account, nessun analytics, nessun tracker, nessun dato inviato a server nostri. Le tue liste, le impostazioni e la storia di lettura vivono solo sul tuo dispositivo.\n\nI dati di catalogo vengono da TMDB e iTunes; le notizie dalle testate italiane indicate nei feed. La posizione, se la attivi, serve solo a ordinare i cinema vicini e non viene memorizzata.")
                            .font(Theme.ui(14)).foregroundColor(Theme.textDim).lineSpacing(4)
                    }
                    .cardSurface()
                }
                .padding(Theme.pad)
            }
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
    }
}

// MARK: - Dashboard AI (curation catalogo)

struct AIDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state = CurationState(promoted: [], hidden: [], generatedAt: nil, note: nil)
    @State private var proposal: (promote: [Movie], hide: [Movie], reasoning: String)?
    @State private var generating = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button(action: { dismiss() }) {
                            Text("‹").font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                                .frame(width: 38, height: 38)
                                .background(Theme.surfaceAlt.cornerRadius(19))
                                .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    Text("Dashboard AI").font(Theme.serif(28)).foregroundColor(Theme.text)
                    Text("La redazione AI valuta il catalogo e propone promozioni ed esclusioni. La proposta non tocca i dati TMDB: viene applicata alla presentazione.")
                        .font(Theme.ui(13)).foregroundColor(Theme.textDim)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("STATO ATTUALE").font(.system(size: 12, weight: .bold)).kerning(1.2).foregroundColor(Theme.textDim)
                        Text("Promossi: \(state.promoted.count) · Nascosti: \(state.hidden.count)")
                            .font(Theme.ui(14, .bold)).foregroundColor(Theme.text)
                        if let note = state.note {
                            Text(note).font(Theme.ui(13)).foregroundColor(Theme.textDim)
                        }
                        GhostButton(label: generating ? "⏳ Valuto il catalogo…" : "✨ Genera la proposta") {
                            Task { await generate() }
                        }
                        .disabled(generating)

                        if let p = proposal {
                            Text(p.reasoning).font(Theme.ui(13)).foregroundColor(Theme.textDim)
                            if !p.promote.isEmpty {
                                Text("PROMUOVI (\(p.promote.count))")
                                    .font(.system(size: 11, weight: .heavy)).kerning(2).foregroundColor(Theme.ok)
                                Text(p.promote.map(\.title).joined(separator: " · "))
                                    .font(Theme.ui(13)).foregroundColor(Theme.text)
                            }
                            if !p.hide.isEmpty {
                                Text("NASCONDI (\(p.hide.count))")
                                    .font(.system(size: 11, weight: .heavy)).kerning(2).foregroundColor(Theme.danger)
                                Text(p.hide.map(\.title).joined(separator: " · "))
                                    .font(Theme.ui(13)).foregroundColor(Theme.text)
                            }
                            PillButton(label: "Applica la proposta") {
                                var s = CurationState(promoted: [], hidden: [], generatedAt: Date(), note: p.reasoning)
                                s.promoted = p.promote.map { String($0.id) }
                                s.hidden = p.hide.map { String($0.id) }
                                Store.saveCuration(s)
                                state = s
                                NotificationCenter.default.post(name: .curationChanged, object: nil)
                            }
                        }
                    }
                    .cardSurface()
                }
                .padding(Theme.pad)
            }
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
        .onAppear { state = Store.loadCuration() }
    }

    private func generate() async {
        generating = true
        let cached = Store.loadMoviesCache()
        let result = Curation.generateProposal(
            now: cached?.nowPlaying ?? [],
            upcoming: cached?.upcoming ?? [],
            popular: cached?.popular ?? [])
        proposal = result
        generating = false
    }
}

// MARK: - Skeleton poster

struct SkeletonPosterCard: View {
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: Theme.radiusSm)
                .fill(Theme.surfaceAlt.opacity(pulsing ? 0.5 : 1))
                .aspectRatio(2/3, contentMode: .fit)
            RoundedRectangle(cornerRadius: 5).fill(Theme.surfaceAlt.opacity(pulsing ? 0.5 : 1)).frame(height: 10)
            RoundedRectangle(cornerRadius: 4.5).fill(Theme.surfaceAlt.opacity(pulsing ? 0.5 : 1)).frame(width: 60, height: 9)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulsing = true }
        }
    }
}

extension Notification.Name {
    static let curationChanged = Notification.Name("cineflash.curationChanged")
}
