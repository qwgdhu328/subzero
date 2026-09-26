import Foundation

// MARK: - Modelli (specchio di src/models/types.ts)

struct NewsItem: Codable, Identifiable, Equatable, Hashable {
    /// id stabile per dedup: hash del link o del titolo.
    let id: String
    let title: String
    let link: String
    let source: String
    let sourceKey: String
    let summary: String
    let publishedAt: String?
    let imageUrl: String?
}

struct NewsSource: Codable, Identifiable, Equatable {
    var key: String
    var name: String
    var url: String
    var enabled: Bool
    var id: String { key }
}

struct Movie: Codable, Identifiable, Equatable {
    let id: Int
    let title: String
    let overview: String
    /// Path TMDB (senza host) oppure URL assoluto (iTunes).
    let posterPath: String?
    /// Voto 0-10; 0 = non disponibile (es. iTunes).
    let voteAverage: Double
    let releaseDate: String?
}

struct Settings: Codable, Equatable {
    var tmdbApiKey: String?
    /// Altri feed RSS aggiunti dall'utente (include le fonti consigliate seminate).
    var customSources: [NewsSource]
    var suggestedSeeded: Bool?
    /// Chiavi delle sorgenti predefinite disabilitate dall'utente.
    var disabledSources: [String]
    var notifyEnabled: Bool?
    /// Live Activity sull'Isola Dinamica per notizie e prevendite.
    var liveActivitiesEnabled: Bool?
    var onboarded: Bool?
}

// MARK: - Film arricchito (dettaglio)

struct DetailMovie: Identifiable, Equatable {
    let movie: Movie
    var trailerUrl: String?
    var runtime: Int?
    var genres: [String]
    var itunesUrl: String?
    var previewUrl: String?
    var longDescription: String?
    var needsTmdb: Bool
    var articleUrl: String?
    var articleSource: String?

    var id: Int { movie.id }
    var title: String { movie.title }
    var posterPath: String? { movie.posterPath }
    var voteAverage: Double { movie.voteAverage }
    var releaseDate: String? { movie.releaseDate }
    var overview: String { movie.overview }
}

// MARK: - Collezioni utente

struct SavedNewsEntry: Codable, Identifiable, Equatable {
    let item: NewsItem
    let savedAt: Date
    var id: String { item.id }
}

struct WatchlistEntry: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let posterPath: String?
    let addedAt: Date
}

struct ReleaseReminder: Codable, Identifiable, Equatable {
    let movieId: String
    let title: String
    let releaseDate: String
    let createdAt: Date
    var id: String { movieId }
}

// MARK: - Articolo AI (redazione)

struct AiArticle: Codable, Identifiable, Equatable {
    /// Stesso id della NewsItem originale (hash del link).
    let id: String
    let title: String
    let standfirst: String
    let paragraphs: [String]
    let images: [String]
    let source: String
    let sourceUrl: String
    let publishedAt: String?
    let rewrittenAt: Date
}

// MARK: - Curation del catalogo (Dashboard AI)

struct CurationState: Codable, Equatable {
    var promoted: [String]
    var hidden: [String]
    var generatedAt: Date?
    var note: String?
}
