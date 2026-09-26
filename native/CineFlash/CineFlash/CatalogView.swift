import SwiftUI
import UIKit
import WebKit

/// Tab "Catalogo": griglia poster con tab (Ora al cinema / In uscita / Popolari),
/// ricerca iTunes, watchlist, ordinamento e scheda film con trailer.
struct CatalogView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: TabKey = .now
    @State private var now: [Movie] = []
    @State private var upcoming: [Movie] = []
    @State private var popular: [Movie] = []
    @State private var loading = true
    @State private var error: String?
    @State private var query = ""
    @State private var results: [Movie]? = nil
    @State private var searching = false
    @State private var savedOnly = false
    @State private var sortBy: SortKey = .none
    @State private var includeReleased = false
    @State private var curation = CurationState(promoted: [], hidden: [], generatedAt: nil, note: nil)
    @State private var detail: DetailMovie?
    @State private var searchTask: Task<Void, Never>?

    enum TabKey: String, CaseIterable { case now, upcoming, popular }
    enum SortKey: String, CaseIterable { case none, vote, date, title }

    private var apiKey: String? { app.settings.tmdbApiKey }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    header
                    grid
                }
                .refreshable { await load(force: true) }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: DetailRoute.self) { route in
                route.destination
            }
            .sheet(item: $detail) { m in
                MovieDetailSheet(movie: m)
                    .environmentObject(app)
                    .presentationDetents([.large])
            }
        }
        .task {
            curation = Store.loadCuration()
            if now.isEmpty && upcoming.isEmpty { await load(force: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .curationChanged)) { _ in
            curation = Store.loadCuration()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(
                eyebrow: todayItalian(),
                title: "Catalogo",
                right: NavigationLink(value: DetailRoute.settings) {
                    Text("⚙").font(.system(size: 13)).foregroundColor(Theme.textDim)
                        .frame(width: 30, height: 30)
                        .background(Theme.surfaceAlt.cornerRadius(15))
                        .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                })

            HStack(spacing: 8) {
                InputField(placeholder: "Cerca un film…", value: $query)
                    .onChange(of: query) { q in
                        searchTask?.cancel()
                        let term = q.trimmingCharacters(in: .whitespaces)
                        guard term.count >= 2 else {
                            if q.isEmpty { results = nil }
                            return
                        }
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            guard !Task.isCancelled else { return }
                            await runSearch(term)
                        }
                    }
                Button(action: { Task { await runSearch(query) } }) {
                    Text("🔍").font(.system(size: 15))
                        .frame(width: 44, height: 44)
                        .background(Theme.surfaceAlt.cornerRadius(12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                if results != nil {
                    Button(action: { query = ""; results = nil }) {
                        Text("✕").font(.system(size: 15))
                            .frame(width: 44, height: 44)
                            .background(Theme.surfaceAlt.cornerRadius(12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            if showTabs {
                ChipRow {
                    FilterChip(label: "📀 Includi già usciti", active: includeReleased) { includeReleased.toggle() }
                    ForEach(sortChips, id: \.0) { key, label in
                        FilterChip(label: label, active: sortBy == key) { sortBy = key }
                    }
                }
                ChipRow {
                    ForEach(visibleTabs, id: \.self) { t in
                        FilterChip(label: tabLabel(t), active: tab == t && !savedOnly) {
                            results = nil; savedOnly = false; tab = t
                        }
                    }
                    FilterChip(label: "⭐ Preferiti (\(app.watchlist.count))", active: savedOnly) {
                        results = nil; savedOnly.toggle()
                    }
                }
            }

            if results != nil {
                Text("\(results!.count) risultati per “\(query.trimmingCharacters(in: .whitespaces))”")
                    .font(Theme.ui(12, .bold)).foregroundColor(Theme.textDim)
            }
            if let e = error {
                Text(e).font(Theme.ui(12)).foregroundColor(Theme.warn)
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 8)
    }

    private var sortChips: [(SortKey, String)] {
        [(.none, "•"), (.vote, "⭐ Voto"), (.date, "📅 Uscita"), (.title, "A–Z")]
    }

    private var visibleTabs: [TabKey] {
        apiKey == nil ? [.now, .upcoming] : TabKey.allCases
    }

    private func tabLabel(_ t: TabKey) -> String {
        switch t {
        case .now: return "🍿 Ora al cinema"
        case .upcoming: return "📅 In uscita"
        case .popular: return "🔥 Popolari"
        }
    }

    private var showTabs: Bool {
        results == nil && (apiKey != nil || !now.isEmpty || !upcoming.isEmpty)
    }

    // MARK: Dati

    private var data: [Movie] {
        let base: [Movie]
        if let r = results {
            base = r
        } else {
            let curated = Curation.apply(tab == .now ? now : tab == .upcoming ? upcoming : popular, curation)
            base = curated
        }
        var list = base
        if !results.hasItems && !includeReleased {
            list = list.filter { !Curation.isAlreadyReleased($0.releaseDate) }
        }
        if savedOnly { list = list.filter { app.isInWatchlist($0.id) } }
        switch sortBy {
        case .vote: list.sort { $0.voteAverage > $1.voteAverage }
        case .title: list.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .date:
            list.sort { a, b in
                let da = Curation.dateFrom(a.releaseDate)?.timeIntervalSince1970 ?? .infinity
                let db = Curation.dateFrom(b.releaseDate)?.timeIntervalSince1970 ?? .infinity
                return da < db
            }
        case .none: break
        }
        return list
    }

    private var grid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 14) {
            if (loading || searching) && data.isEmpty {
                ForEach(0..<6, id: \.self) { _ in SkeletonPosterCard() }
            } else if data.isEmpty {
                EmptyStateView(icon: results != nil ? "🔍" : "🎞️",
                               title: results != nil ? "Nessun risultato" : "Nessun film",
                               subtitle: results != nil ? "Prova con un altro titolo." : "Riprova con l'aggiornamento (tira giù la lista).")
            } else {
                ForEach(data) { m in
                    MovieCard(movie: m) { openDetail(m) }
                }
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 14)
        .padding(.bottom, 32)
    }

    private func load(force: Bool) async {
        error = nil
        if let key = apiKey {
            if !force, let cached = Store.loadMoviesCache(), cached.provider == "tmdb" {
                now = cached.nowPlaying; upcoming = cached.upcoming; popular = cached.popular
                loading = false
            }
            do {
                async let np = TMDBService.fetchNowPlaying(apiKey: key)
                async let up = TMDBService.fetchUpcoming(apiKey: key)
                async let pop = TMDBService.fetchPopular(apiKey: key)
                let (a, b, c) = try await (np, up, pop)
                now = a; upcoming = b; popular = c
                Store.saveMoviesCache(Store.MoviesCache(
                    fetchedAt: Date(), provider: "tmdb", nowPlaying: a, upcoming: b, popular: c))
            } catch {
                self.error = "Errore TMDB"
            }
        } else {
            let newReleases = await ItunesService.fetchNewReleases()
            let store = (try? await ItunesService.fetchMovies()) ?? []
            let nowList = newReleases.isEmpty ? store : newReleases
            let seen = Set(nowList.map(\.id))
            now = nowList.map(\.asMovie)
            upcoming = store.filter { !seen.contains($0.id) }.map(\.asMovie)
            popular = []
            Store.saveMoviesCache(Store.MoviesCache(
                fetchedAt: Date(), provider: "itunes",
                nowPlaying: now, upcoming: upcoming, popular: []))
        }
        loading = false
    }

    private func runSearch(_ term: String) async {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return }
        searching = true
        error = nil
        do {
            let r = try await ItunesService.searchMovies(t)
            results = r.map(\.asMovie)
        } catch {
            self.error = "Ricerca non riuscita, riprova."
        }
        searching = false
    }

    private func openDetail(_ m: Movie) {
        detail = DetailMovie(movie: m, trailerUrl: nil, runtime: nil, genres: [],
                             itunesUrl: nil, previewUrl: nil, longDescription: nil,
                             needsTmdb: apiKey != nil, articleUrl: nil, articleSource: nil)
        if let key = apiKey {
            Task {
                if let det = try? await TMDBService.fetchMovieDetails(apiKey: key, movieId: m.id) {
                    if detail?.id == m.id {
                        detail?.trailerUrl = det.trailerUrl
                        detail?.runtime = det.runtime
                        detail?.genres = det.genres
                    }
                }
            }
        }
    }
}

extension Optional where Wrapped == [Movie] {
    var hasItems: Bool {
        switch self {
        case .some(let list): return !list.isEmpty
        case .none: return false
        }
    }
}

// MARK: - Card film

struct MovieCard: View {
    @EnvironmentObject var app: AppState
    let movie: Movie
    let onPress: () -> Void

    private var starred: Bool { app.isInWatchlist(movie.id) }

    /// Nastro di stato: IN ARRIVO / IN USCITA.
    private var ribbon: String? {
        guard let iso = movie.releaseDate, let d = Curation.dateFrom(iso) else { return nil }
        let days = Int(ceil(d.timeIntervalSinceNow / 86_400))
        if days > 0 && days <= 60 { return "IN ARRIVO" }
        if days <= 0 && days >= -7 { return "IN USCITA" }
        return nil
    }

    var body: some View {
        Button(action: onPress) {
            VStack(alignment: .leading, spacing: 0) {
                PosterView(url: TMDBService.posterUrl(movie.posterPath))
                    .overlay(alignment: .topLeading) {
                        if movie.voteAverage > 0 {
                            Text(String(format: "%.1f", movie.voteAverage))
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.black.opacity(0.82).cornerRadius(8))
                                .padding(6)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let ribbon {
                            Text(ribbon)
                                .font(.system(size: 9, weight: .heavy)).kerning(0.8)
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.black.opacity(0.82).cornerRadius(6))
                                .padding(6)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button(action: {
                            _ = app.toggleWatchlist(WatchlistEntry(
                                id: String(movie.id), title: movie.title,
                                posterPath: movie.posterPath, addedAt: Date()))
                        }) {
                            Text(starred ? "⭐" : "☆").font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(Color.black.opacity(0.65).cornerRadius(16))
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                    }

                Text(movie.title)
                    .font(Theme.ui(13, .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .padding(.top, 8)
                HStack {
                    if movie.voteAverage > 0 {
                        Text("⭐ \(String(format: "%.1f", movie.voteAverage))")
                            .font(.system(size: 12, weight: .heavy)).foregroundColor(Theme.accent)
                    }
                    Spacer()
                    Text(movie.releaseDate.map { fmtReleaseDate($0) } ?? "")
                        .font(Theme.ui(10)).foregroundColor(Theme.textDim).lineLimit(1)
                }
                .padding(.top, 4)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scheda film (sheet)

struct MovieDetailSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let movie: DetailMovie
    @State private var showAI = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        PosterView(url: TMDBService.posterUrl(movie.posterPath, size: "w500"))
                            .frame(width: 110)
                        VStack(alignment: .leading, spacing: 6) {
                            if movie.voteAverage > 0 {
                                Badge(label: "⭐ \(String(format: "%.1f", movie.voteAverage))/10", tone: Theme.accent)
                            }
                            Text(fmtReleaseDate(movie.releaseDate))
                                .font(Theme.ui(13, .bold)).foregroundColor(Theme.text)
                            if let r = movie.runtime {
                                Text("\(r) min").font(Theme.ui(12)).foregroundColor(Theme.textDim)
                            }
                            if !movie.genres.isEmpty {
                                Text(movie.genres.joined(separator: " · "))
                                    .font(Theme.ui(12)).foregroundColor(Theme.textDim).lineLimit(2)
                            }
                        }
                        Spacer()
                    }

                    if let trailer = movie.trailerUrl.flatMap(YouTubeSupport.videoID) {
                        YouTubeEmbed(videoID: trailer)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                    } else if let mp4 = movie.previewUrl.flatMap(URL.init) {
                        Text("▶️ Trailer disponibile (anteprima Apple)")
                            .font(Theme.ui(12)).foregroundColor(Theme.textDim)
                        Link(destination: mp4) {
                            Text("Apri il trailer").font(Theme.ui(14, .semibold)).foregroundColor(Theme.accent)
                        }
                    }

                    Text(movie.overview.isEmpty ? (movie.longDescription ?? "Trama non disponibile.") : movie.overview)
                        .font(Theme.ui(14)).foregroundColor(Theme.textDim).lineSpacing(4)

                    VStack(spacing: 6) {
                        PillButton(label: "✨  Spiega con l'AI") {
                            showAI = true
                        }
                        GhostButton(label: app.isInWatchlist(movie.id) ? "✓  Nella watchlist — tocca per rimuovere" : "☆  Aggiungi alla watchlist") {
                            _ = app.toggleWatchlist(WatchlistEntry(
                                id: String(movie.id), title: movie.title,
                                posterPath: movie.posterPath, addedAt: Date()))
                        }
                        GhostButton(label: "🔍 Leggi le recensioni") {
                            let q = "recensione " + movie.title
                            if let url = URL(string: "https://www.google.com/search?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)") {
                                UIApplication.shared.open(url)
                            }
                        }
                        if let itunes = movie.itunesUrl.flatMap(URL.init) {
                            Link(destination: itunes) {
                                Text("🍎 Apri in iTunes Store")
                                    .font(Theme.ui(14, .semibold)).foregroundColor(Theme.text)
                                    .padding(.vertical, 15).padding(.horizontal, 22)
                                    .frame(maxWidth: .infinity)
                                    .background(Theme.surfaceAlt.cornerRadius(999))
                            }
                        }
                    }
                }
                .padding(Theme.pad)
            }
            .background(Theme.surface)
            .navigationTitle(movie.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showAI) {
                AIChatView(mode: "movie", ctxTitle: movie.title,
                           ctxText: "Trama: \(movie.overview). Generi: \(movie.genres.joined(separator: ", ")).",
                           ctxSource: nil)
            }
        }
    }
}

// MARK: - YouTube helpers

enum YouTubeSupport {
    static func videoID(_ url: String) -> String? {
        let patterns = ["v=", "youtu.be/", "embed/", "shorts/"]
        for p in patterns {
            if let range = url.range(of: p) {
                let id = String(url[range.upperBound...]).prefix(11)
                if id.count == 11 { return String(id) }
            }
        }
        return nil
    }
}

struct YouTubeEmbed: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.scrollView.isScrollEnabled = false
        return wv
    }
    func updateUIView(_ wv: WKWebView, context: Context) {
        let html = "<iframe width=\"100%\" height=\"100%\" src=\"https://www.youtube.com/embed/\(videoID)?rel=0\" frameborder=\"0\" allowfullscreen></iframe>"
        wv.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Riga di chip scrollabile orizzontale

struct ChipRow<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { content() }
        }
    }
}
