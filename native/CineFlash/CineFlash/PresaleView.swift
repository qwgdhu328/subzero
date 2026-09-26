import SwiftUI

/// Pagina PREVENDITE: film in evidenza con countdown, griglia a sezioni e
/// prenotazione rapida (città → cinema reali OSM → sito del cinema).
struct PresaleView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var movies: [Movie] = []
    @State private var loading = true
    @State private var error: String?
    @State private var sortBy: PresaleSort = .date
    @State private var curation = CurationState(promoted: [], hidden: [], generatedAt: nil, note: nil)
    @State private var detail: DetailMovie?
    @State private var bookingMovie: Movie?
    @State private var nowTick = Date()

    enum PresaleSort: String, CaseIterable { case date, vote, title }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                header
                if let featured {
                    featuredCard(featured)
                }
                if let e = error {
                    Text(e).font(Theme.ui(12)).foregroundColor(Theme.warn).padding(.horizontal, Theme.pad)
                }
                sectionsView
            }
            .refreshable { await load(force: true) }
        }
        .navigationBarHidden(true)
        .sheet(item: $detail) { m in
            MovieDetailSheet(movie: m).environmentObject(app)
        }
        .sheet(item: $bookingMovie) { m in
            BookingSheet(movieTitle: m.title)
        }
        .task {
            curation = Store.loadCuration()
            if movies.isEmpty { await load(force: false) }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { t in
            nowTick = t
        }
        .onReceive(NotificationCenter.default.publisher(for: .curationChanged)) { _ in
            curation = Store.loadCuration()
        }
    }

    // MARK: Dati

    private var curated: [Movie] {
        Curation.apply(movies, curation).filter { !Curation.isAlreadyReleased($0.releaseDate) }
    }

    private var featured: Movie? {
        let withDays = curated.compactMap { m -> (Movie, Int)? in
            guard let d = Curation.daysUntil(m.releaseDate), d >= -2 else { return nil }
            return (m, d)
        }.sorted { $0.1 < $1.1 }
        return withDays.first?.0 ?? curated.first
    }

    private var rest: [Movie] {
        var list = curated.filter { $0.id != featured?.id }
        switch sortBy {
        case .vote: list.sort { $0.voteAverage > $1.voteAverage }
        case .title: list.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .date:
            list.sort { a, b in
                let da = Curation.dateFrom(a.releaseDate)?.timeIntervalSince1970 ?? .infinity
                let db = Curation.dateFrom(b.releaseDate)?.timeIntervalSince1970 ?? .infinity
                return da < db
            }
        }
        return list
    }

    private var sections: [(label: String, items: [Movie])] {
        guard sortBy == .date else { return [("TUTTI I TITOLI", rest)] }
        var buckets: [(String, [Movie])] = [
            ("IN USCITA ORA", []), ("QUESTA SETTIMANA", []), ("PIÙ AVANTI", []), ("DATA DA DEFINIRE", []),
        ]
        for m in rest {
            let d = Curation.daysUntil(m.releaseDate)
            if d == nil { buckets[3].1.append(m) }
            else if d! <= 0 { buckets[0].1.append(m) }
            else if d! <= 7 { buckets[1].1.append(m) }
            else { buckets[2].1.append(m) }
        }
        return buckets.filter { !$0.1.isEmpty }
    }

    // MARK: UI

    private var header: some View {
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
                EyebrowText(text: "CineFlash · Biglietti")
                Text("Prevendite")
                    .font(Theme.serif(32)).foregroundColor(Theme.text)
            }
            ChipRow {
                ForEach([PresaleSort.date, .vote, .title], id: \.self) { key in
                    FilterChip(
                        label: key == .date ? "📅 Data" : key == .vote ? "⭐ Voto" : "A–Z",
                        active: sortBy == key) { sortBy = key }
                }
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 8)
    }

    private func featuredCard(_ f: Movie) -> some View {
        Button(action: { openDetail(f) }) {
            HStack(alignment: .top, spacing: 14) {
                PosterView(url: TMDBService.posterUrl(f.posterPath, size: "w500"))
                    .frame(width: 112)
                VStack(alignment: .leading, spacing: 6) {
                    Text(releaseKicker(f.releaseDate))
                        .font(.system(size: 10, weight: .heavy)).kerning(2)
                        .foregroundColor(Theme.accent)
                    countdown(for: f.releaseDate)
                        .font(.system(size: 13, weight: .heavy)).kerning(1)
                        .foregroundColor(Theme.accent)
                    Text(f.title)
                        .font(Theme.serif(20)).foregroundColor(Theme.text).lineLimit(3)
                    Text(fmtReleaseDate(f.releaseDate))
                        .font(Theme.ui(12)).foregroundColor(Theme.textDim)
                    Button(action: { bookingMovie = f }) {
                        Text("🎟️  Prenota ora")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(Theme.onAccent)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Theme.surfaceRaised, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .cornerRadius(Theme.radiusXl)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusXl).stroke(Theme.border, lineWidth: 0.5))
            .padding(.horizontal, Theme.pad)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func countdown(for iso: String?) -> some View {
        let target = Curation.dateFrom(iso).map { d -> Date in
            var c = Calendar.current.dateComponents([.year, .month, .day], from: d)
            c.hour = 9
            return Calendar.current.date(from: c) ?? d
        }
        if let target, target > nowTick {
            let diff = target.timeIntervalSince(nowTick)
            let days = Int(diff / 86_400)
            let hours = Int(diff.truncatingRemainder(dividingBy: 86_400) / 3_600)
            let mins = Int(diff.truncatingRemainder(dividingBy: 3_600) / 60)
            Text("\(days > 0 ? "\(days)g " : "")\(String(format: "%02d", hours)):\(String(format: "%02d", mins))")
        }
    }

    private var sectionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, sec in
                HStack(spacing: 8) {
                    Text(sec.label)
                        .font(.system(size: 11, weight: .heavy)).kerning(2.5)
                        .foregroundColor(Theme.accent)
                    Text("\(sec.items.count)")
                        .font(Theme.ui(11, .bold)).foregroundColor(Theme.textDim)
                    Rectangle().fill(Theme.border).frame(height: 0.5)
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 18)
                .padding(.bottom, 12)

                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sec.items) { m in
                        PresaleCard(movie: m) {
                            openDetail(m)
                        } onBook: {
                            bookingMovie = m
                        }
                    }
                }
                .padding(.horizontal, Theme.pad)
            }

            if loading && movies.isEmpty {
                VStack(spacing: 8) {
                    Text("Carico i film prenotabili…")
                        .font(Theme.ui(13)).foregroundColor(Theme.textDim)
                }
                .padding(.top, 60)
            } else if rest.isEmpty {
                EmptyStateView(icon: "🎟️", title: "Nessun film in prevendita",
                               subtitle: "Tira giù per aggiornare l'elenco dei titoli in uscita.")
            }
        }
    }

    private func openDetail(_ m: Movie) {
        detail = DetailMovie(movie: m, trailerUrl: nil, runtime: nil, genres: [],
                             itunesUrl: nil, previewUrl: nil, longDescription: nil,
                             needsTmdb: true, articleUrl: nil, articleSource: nil)
        if let key = app.settings.tmdbApiKey {
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

    private func load(force: Bool) async {
        error = nil
        if !force, let cached = Store.loadMoviesCache(), cached.provider == "tmdb" {
            movies = cached.upcoming
            loading = false
        }
        do {
            let up = try await TMDBService.fetchUpcoming(apiKey: Store.builtInTmdbApiKey)
            movies = up
            var cached = Store.loadMoviesCache()
            Store.saveMoviesCache(Store.MoviesCache(
                fetchedAt: Date(), provider: "tmdb",
                nowPlaying: cached?.nowPlaying ?? [], upcoming: up,
                popular: cached?.popular ?? []))
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

func releaseKicker(_ iso: String?) -> String {
    guard let d = Curation.daysUntil(iso) else { return "IN USCITA" }
    if d <= 0 { return "AL CINEMA DA OGGI" }
    if d == 1 { return "ESCE DOMANI" }
    return "ESCE TRA \(d) GIORNI"
}

// MARK: - Card presale

struct PresaleCard: View {
    @EnvironmentObject var app: AppState
    let movie: Movie
    let onPress: () -> Void
    let onBook: () -> Void

    private var days: Int? { Curation.daysUntil(movie.releaseDate) }
    private var starred: Bool { app.isInWatchlist(movie.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PosterView(url: TMDBService.posterUrl(movie.posterPath))
                .overlay(alignment: .topLeading) {
                    if let days, days >= 0, days <= 14 {
                        Text(days == 0 ? "OGGI" : days == 1 ? "DOMANI" : "TRA \(days) G")
                            .font(.system(size: 9, weight: .heavy)).kerning(0.8)
                            .foregroundColor(Theme.onAccent)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.accent.cornerRadius(6))
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button(action: {
                        _ = app.toggleWatchlist(WatchlistEntry(
                            id: String(movie.id), title: movie.title,
                            posterPath: movie.posterPath, addedAt: Date()))
                    }) {
                        Text(starred ? "⭐" : "☆").font(.system(size: 14))
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.72).cornerRadius(15))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }

            Text(movie.title)
                .font(Theme.ui(13, .bold)).foregroundColor(Theme.text).lineLimit(2)
                .padding(.top, 9)
            Text(fmtReleaseDate(movie.releaseDate))
                .font(Theme.ui(10)).foregroundColor(Theme.textDim)
                .padding(.top, 2).padding(.bottom, 10)

            Button(action: onBook) {
                Text("PRENOTA")
                    .font(.system(size: 10, weight: .heavy)).kerning(1.5)
                    .foregroundColor(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Theme.surfaceRaised.cornerRadius(Theme.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).stroke(Theme.border, lineWidth: 0.5))
        .onTapGesture { onPress() }
    }
}

// MARK: - Booking sheet (città → cinema)

struct BookingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let movieTitle: String
    @State private var city = ""
    @State private var cinemas: [Cinema]?
    @State private var loading = false
    @State private var error: String?
    @State private var searchedCity = ""
    @State private var locating = false

    private let citySuggestions = ["Roma", "Milano", "Napoli", "Torino", "Firenze", "Bologna", "Verona", "Bari"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if cinemas == nil {
                        Text("IN QUALE CITTÀ?")
                            .font(.system(size: 12, weight: .heavy)).kerning(1.2)
                            .foregroundColor(Theme.textDim)

                        Button(action: { Task { await locateAndSearch() } }) {
                            HStack {
                                if locating {
                                    ProgressView().tint(Theme.accent)
                                    Text("Rilevo la posizione…")
                                } else {
                                    Text("📍 Usa la mia posizione")
                                }
                            }
                            .font(Theme.ui(14, .semibold)).foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.surfaceAlt.cornerRadius(Theme.radiusMd))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).stroke(Theme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(locating || loading)

                        InputField(placeholder: "Scrivi la città…", value: $city)
                            .onSubmit { Task { await search(city) } }

                        ChipRow {
                            ForEach(citySuggestions, id: \.self) { c in
                                FilterChip(label: c, active: false) {
                                    city = c
                                    Task { await search(c) }
                                }
                            }
                        }

                        GhostButton(label: "Cerca i cinema") { Task { await search(city) } }
                    } else {
                        HStack {
                            Text("\(cinemas!.count) cinema a \(searchedCity)")
                                .font(Theme.ui(14, .bold)).foregroundColor(Theme.text)
                            Spacer()
                            Button("Cambia città") {
                                cinemas = nil
                            }
                            .font(Theme.ui(13, .semibold)).foregroundColor(Theme.accent)
                        }

                        ForEach(cinemas!) { c in
                            CinemaRow(cinema: c, movieTitle: movieTitle, city: searchedCity)
                        }
                        if cinemas!.isEmpty {
                            EmptyStateView(icon: "🎬", title: "Nessun cinema trovato",
                                           subtitle: "Prova con una città diversa.")
                        }
                    }

                    if let e = error {
                        Text(e).font(Theme.ui(12)).foregroundColor(Theme.warn)
                    }
                }
                .padding(Theme.pad)
            }
            .background(Theme.surface)
            .navigationTitle("Prenota · \(movieTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
        }
    }

    private func search(_ name: String) async {
        let c = name.trimmingCharacters(in: .whitespaces)
        guard c.count >= 2 else { return }
        loading = true
        error = nil
        searchedCity = c
        Store.lastCity = c
        do {
            cinemas = try await CinemasService.fetchByCity(c)
        } catch {
            self.error = "Impossibile scaricare l'elenco cinema. Riprova."
            cinemas = nil
        }
        loading = false
    }

    private func locateAndSearch() async {
        locating = true
        error = nil
        if let loc = await CinemasService.currentLocation() {
            let detected = await CinemasService.cityFromLocation(loc) ?? ""
            if !detected.isEmpty {
                city = detected
                await search(detected)
            } else {
                error = "Non sono riuscito a rilevare la città: controlla il permesso posizione o scrivi la città a mano."
            }
        } else {
            error = "Non sono riuscito a rilevare la città: controlla il permesso posizione o scrivi la città a mano."
        }
        locating = false
    }
}

struct CinemaRow: View {
    let cinema: Cinema
    let movieTitle: String
    let city: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: {
            let target = CinemasService.bookingUrl(cinema: cinema, movieTitle: movieTitle, cityName: city)
            if let url = URL(string: target.url) { openURL(url) }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cinema.name).font(Theme.ui(15, .bold)).foregroundColor(Theme.text)
                    if let addr = cinema.address {
                        Text(addr).font(Theme.ui(12)).foregroundColor(Theme.textDim).lineLimit(1)
                    }
                    if let km = cinema.distanceKm {
                        Text(String(format: "%.1f km", km)).font(Theme.ui(11)).foregroundColor(Theme.accent)
                    }
                }
                Spacer()
                Text("PRENOTA")
                    .font(.system(size: 10, weight: .heavy)).kerning(1.5)
                    .foregroundColor(Theme.accent)
                Text("›").foregroundColor(Theme.textDim)
            }
            .padding(12)
            .background(Theme.surface.cornerRadius(Theme.radiusMd))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).stroke(Theme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
