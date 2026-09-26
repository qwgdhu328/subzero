import Foundation

// MARK: - Store: persistenza locale (porting di store.ts + collections.ts)

enum Store {
    private static let defaults = UserDefaults.standard
    private static let keySettings = "cineflash/settings/v1"
    private static let keyNewsCache = "cineflash/news-cache/v1"
    private static let keyMoviesCache = "cineflash/movies-cache/v1"
    private static let keyAiArticles = "cineflash/ai-articles/v1"
    private static let keySavedNews = "cineflash/saved-news/v1"
    private static let keyWatchlist = "cineflash/watchlist/v1"
    private static let keyReminders = "cineflash/reminders/v1"
    private static let keyLastCity = "cineflash/last-city/v1"
    private static let keyCuration = "cineflash/movie-curation/v1"
    private static let keyReadHistory = "cineflash/read-history/v1"

    // MARK: Fonti predefinite (URL verificati)

    static let defaultSources: [NewsSource] = [
        NewsSource(key: "ansa", name: "ANSA Cinema", url: "https://www.ansa.it/sito/notizie/cultura/cinema/cinema_rss.xml", enabled: true),
        NewsSource(key: "badtaste", name: "BadTaste", url: "https://www.badtaste.it/feed", enabled: true),
        NewsSource(key: "cineblog", name: "CineBlog", url: "https://www.cineblog.it/feed", enabled: true),
        NewsSource(key: "ciak", name: "Ciak Magazine", url: "https://www.ciakmagazine.it/feed/", enabled: true),
        NewsSource(key: "comingsoon", name: "ComingSoon.it", url: "https://www.comingsoon.it/feedrss/", enabled: true),
    ]

    static let suggestedSources: [NewsSource] = [
        NewsSource(key: "suggested_everyeye", name: "Everyeye Cinema", url: "https://cinema.everyeye.it/feed/", enabled: true),
        NewsSource(key: "suggested_bestmovie", name: "Best Movie", url: "https://www.bestmovie.it/feed/", enabled: true),
        NewsSource(key: "suggested_screenweek", name: "ScreenWeek", url: "https://www.screenweek.it/feed/", enabled: true),
        NewsSource(key: "suggested_cinefiliaritrovata", name: "Cinefilia Ritrovata", url: "https://www.cinefiliaritrovata.it/feed/", enabled: true),
        NewsSource(key: "suggested_filmidee", name: "FilmIdee", url: "https://www.filmidee.it/feed/", enabled: true),
        NewsSource(key: "suggested_spaziofilm", name: "SpazioFilm", url: "https://www.spaziofilm.it/feed/", enabled: true),
        NewsSource(key: "suggested_nocturno", name: "Nocturno", url: "https://www.nocturno.it/feed/", enabled: true),
    ]

    /// Chiave TMDB inclusa nell'app: la tab Film funziona out-of-the-box.
    static let builtInTmdbApiKey = "ea95fe5f63cc25fb347f0d7c813bb40a"

    static var defaultSettings: Settings {
        Settings(
            tmdbApiKey: builtInTmdbApiKey,
            customSources: [],
            suggestedSeeded: nil,
            disabledSources: [],
            notifyEnabled: true,
            onboarded: false
        )
    }

    // MARK: Settings

    static func loadSettings() -> Settings {
        guard let raw = defaults.string(forKey: keySettings),
              let data = raw.data(using: .utf8),
              var parsed = try? JSONDecoder().decode(Settings.self, from: data) else {
            return seedSuggested(defaultSettings)
        }
        if parsed.tmdbApiKey == nil || parsed.tmdbApiKey?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            parsed.tmdbApiKey = builtInTmdbApiKey
        }
        return seedSuggested(parsed)
    }

    private static func seedSuggested(_ s: Settings) -> Settings {
        if s.suggestedSeeded == true { return s }
        let existing = Set(s.customSources.map(\.key))
        let toAdd = suggestedSources.filter { !existing.contains($0.key) }
        var out = s
        out.customSources += toAdd
        out.suggestedSeeded = true
        return out
    }

    static func saveSettings(_ s: Settings) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(String(data: data, encoding: .utf8), forKey: keySettings)
    }

    static func activeSources(_ settings: Settings) -> [NewsSource] {
        var defaultsList = Self.defaultSources
        for i in defaultsList.indices where settings.disabledSources.contains(defaultsList[i].key) {
            defaultsList[i].enabled = false
        }
        return (defaultsList + settings.customSources).filter(\.enabled)
    }

    // MARK: Cache notizie

    struct NewsCache: Codable {
        var fetchedAt: Date
        var items: [NewsItem]
    }

    static func loadNewsCache() -> NewsCache? {
        guard let raw = defaults.string(forKey: keyNewsCache),
              let data = raw.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(NewsCache.self, from: data)
    }

    static func saveNewsCache(_ cache: NewsCache) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(cache) else { return }
        defaults.set(String(data: data, encoding: .utf8), forKey: keyNewsCache)
    }

    // MARK: Cache film

    struct MoviesCache: Codable {
        var fetchedAt: Date
        var provider: String
        var nowPlaying: [Movie]
        var upcoming: [Movie]
        var popular: [Movie]
    }

    static func loadMoviesCache() -> MoviesCache? {
        guard let raw = defaults.string(forKey: keyMoviesCache),
              let data = raw.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(MoviesCache.self, from: data)
    }

    static func saveMoviesCache(_ cache: MoviesCache) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(cache) else { return }
        defaults.set(String(data: data, encoding: .utf8), forKey: keyMoviesCache)
    }

    // MARK: Articoli AI

    static func loadAiArticles() -> [String: AiArticle] {
        guard let raw = defaults.string(forKey: keyAiArticles),
              let data = raw.data(using: .utf8) else { return [:] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([String: AiArticle].self, from: data)) ?? [:]
    }

    static func saveAiArticle(_ art: AiArticle) {
        var map = loadAiArticles()
        map[art.id] = art
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(map) {
            defaults.set(String(data: data, encoding: .utf8), forKey: keyAiArticles)
        }
    }

    // MARK: Salvati / watchlist / promemoria

    static func loadSavedNews() -> [SavedNewsEntry] { load([SavedNewsEntry].self, keySavedNews) ?? [] }
    static func saveSavedNews(_ list: [SavedNewsEntry]) { save(list, keySavedNews) }

    static func loadWatchlist() -> [WatchlistEntry] { load([WatchlistEntry].self, keyWatchlist) ?? [] }
    static func saveWatchlist(_ list: [WatchlistEntry]) { save(list, keyWatchlist) }

    static func loadReminders() -> [ReleaseReminder] { load([ReleaseReminder].self, keyReminders) ?? [] }
    static func saveReminders(_ list: [ReleaseReminder]) { save(list, keyReminders) }

    static func toggleSaved(_ item: NewsItem) -> Bool {
        var list = loadSavedNews()
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            list.remove(at: idx)
            saveSavedNews(list)
            return false
        }
        list.insert(SavedNewsEntry(item: item, savedAt: Date()), at: 0)
        saveSavedNews(list)
        return true
    }

    static func toggleWatchlist(_ entry: WatchlistEntry) -> Bool {
        var list = loadWatchlist()
        if let idx = list.firstIndex(where: { $0.id == entry.id }) {
            list.remove(at: idx)
            saveWatchlist(list)
            return false
        }
        list.insert(entry, at: 0)
        saveWatchlist(list)
        return true
    }

    static func toggleReminder(_ r: ReleaseReminder) -> Bool {
        var list = loadReminders()
        if let idx = list.firstIndex(where: { $0.movieId == r.movieId }) {
            list.remove(at: idx)
            saveReminders(list)
            return false
        }
        list.append(r)
        saveReminders(list)
        return true
    }

    static var lastCity: String? {
        get { defaults.string(forKey: keyLastCity) }
        set { defaults.set(newValue, forKey: keyLastCity) }
    }

    // MARK: Storia di lettura

    static func loadReadHistory() -> [String] { load([String].self, keyReadHistory) ?? [] }
    static func markRead(_ id: String) {
        var list = loadReadHistory()
        if list.contains(id) { return }
        list.insert(id, at: 0)
        save(Array(list.prefix(300)), keyReadHistory)
    }

    // MARK: Curation

    static func loadCuration() -> CurationState {
        guard let raw = defaults.string(forKey: keyCuration),
              let data = raw.data(using: .utf8) else { return CurationState(promoted: [], hidden: [], generatedAt: nil, note: nil) }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(CurationState.self, from: data))
            ?? CurationState(promoted: [], hidden: [], generatedAt: nil, note: nil)
    }

    static func saveCuration(_ c: CurationState) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(c) {
            defaults.set(String(data: data, encoding: .utf8), forKey: keyCuration)
        }
    }

    // MARK: Helpers

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let raw = defaults.string(forKey: key), let data = raw.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(value) else { return }
        defaults.set(String(data: data, encoding: .utf8), forKey: key)
    }
}

// MARK: - Curation helpers (porting di movieCuration.ts)

enum Curation {
    static func apply(_ list: [Movie], _ state: CurationState) -> [Movie] {
        let promoted = Set(state.promoted)
        let hidden = Set(state.hidden)
        return list
            .filter { !hidden.contains(String($0.id)) }
            .sorted { a, b in
                let pa = promoted.contains(String(a.id)) ? 0 : 1
                let pb = promoted.contains(String(b.id)) ? 0 : 1
                return pa < pb
            }
    }

    static func isAlreadyReleased(_ releaseDate: String?, graceDays: Int = 7) -> Bool {
        guard let releaseDate, let d = dateFrom(releaseDate) else { return false }
        return Date().timeIntervalSince(d) > Double(graceDays) * 86_400
    }

    static func dateFrom(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        if let d = ISO8601DateFormatter().date(from: iso) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(iso.prefix(10)))
    }

    /// Giorni mancanti all'uscita (null se data assente o invalida).
    static func daysUntil(_ iso: String?) -> Int? {
        guard let d = dateFrom(iso) else { return nil }
        return Int(ceil((d.timeIntervalSinceNow / 86_400)))
    }

    /// Genera la proposta di redazione (euristiche deterministiche).
    static func generateProposal(now: [Movie], upcoming: [Movie], popular: [Movie]) -> (promote: [Movie], hide: [Movie], reasoning: String) {
        var all: [Int: Movie] = [:]
        for m in now + upcoming + popular { all[m.id] = m }
        let catalog = Array(all.values)

        var promotedSet = Set<Int>()
        var hiddenSet = Set<Int>()

        for m in catalog {
            let days = m.releaseDate.flatMap { daysUntil($0) }
            if m.voteAverage >= 7.0, let days, days <= 30 { promotedSet.insert(m.id) }
            if m.voteAverage > 0, m.voteAverage < 5.0, let days, days > 60 { hiddenSet.insert(m.id) }
            if m.overview.trimmingCharacters(in: .whitespaces).count < 40 { hiddenSet.insert(m.id) }
            if let days, days < -90 { hiddenSet.insert(m.id) }
        }

        var reasons: [String] = []
        let promoteList = catalog.filter { promotedSet.contains($0.id) }
        let hideList = catalog.filter { hiddenSet.contains($0.id) }
        if !promoteList.isEmpty {
            reasons.append("\(promoteList.count) titoli promossi: voto alto e uscita entro 30 giorni.")
        }
        if !hideList.isEmpty {
            reasons.append("\(hideList.count) titoli nascosti: voto basso, trama assente o uscita fuori finestra.")
        }
        if reasons.isEmpty { reasons.append("Catalogo in ordine: nessuna modifica necessaria.") }

        return (promoteList, hideList, reasons.joined(separator: " "))
    }
}
