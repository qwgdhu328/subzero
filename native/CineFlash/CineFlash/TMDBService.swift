import Foundation

// MARK: - TMDB (porting di src/logic/tmdb.ts)

enum TMDBService {
    private static let base = "https://api.themoviedb.org/3"
    private static let img = "https://image.tmdb.org/t/p/"

    static func posterUrl(_ path: String?, size: String = "w342") -> String? {
        guard let path else { return nil }
        if path.hasPrefix("http") { return path }
        return "\(img)\(size)\(path)"
    }

    static func isV4Token(_ token: String) -> Bool {
        token.hasPrefix("eyJ") && token.components(separatedBy: ".").count == 3
    }

    private struct ListResponse: Decodable {
        var results: [RawMovie]?
    }
    private struct RawMovie: Decodable {
        var id: Int
        var title: String?
        var original_title: String?
        var overview: String?
        var poster_path: String?
        var vote_average: Double?
        var release_date: String?
        var runtime: Int?
        var genres: [Genre]?
        var name: String?
        var key: String?
        var site: String?
        var type: String?
    }
    private struct Genre: Decodable { var name: String }

    struct Details {
        var trailerUrl: String?
        var runtime: Int?
        var genres: [String]
    }

    private static func get(_ path: String, apiKey: String, query: [String: String] = [:]) async throws -> Data {
        var comps = URLComponents(string: "\(base)\(path)")
        var items = [URLQueryItem(name: "language", value: "it-IT")]
        for (k, v) in query { items.append(URLQueryItem(name: k, value: v)) }
        if isV4Token(apiKey) {
            comps?.queryItems = items
        } else {
            items.append(URLQueryItem(name: "api_key", value: apiKey))
            comps?.queryItems = items
        }
        var req = URLRequest(url: comps!.url!)
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if isV4Token(apiKey) {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static func fetchNowPlaying(apiKey: String) async throws -> [Movie] {
        let d = try await get("/movie/now_playing", apiKey: apiKey)
        return try JSONDecoder().decode(ListResponse.self, from: d).results.map(mapMovie) ?? []
    }

    static func fetchUpcoming(apiKey: String) async throws -> [Movie] {
        let d = try await get("/movie/upcoming", apiKey: apiKey)
        return try JSONDecoder().decode(ListResponse.self, from: d).results.map(mapMovie) ?? []
    }

    static func fetchPopular(apiKey: String) async throws -> [Movie] {
        let d = try await get("/movie/popular", apiKey: apiKey)
        return try JSONDecoder().decode(ListResponse.self, from: d).results.map(mapMovie) ?? []
    }

    private static func mapMovie(_ r: RawMovie) -> Movie {
        Movie(
            id: r.id,
            title: r.title ?? r.original_title ?? "—",
            overview: r.overview ?? "",
            posterPath: r.poster_path,
            voteAverage: r.vote_average ?? 0,
            releaseDate: r.release_date
        )
    }

    static func fetchMovieDetails(apiKey: String, movieId: Int) async throws -> Details {
        async let det: ListResponse = get("/movie/\(movieId)", apiKey: apiKey).decode()
        async let vids: ListResponse = get("/movie/\(movieId)/videos", apiKey: apiKey).decode()
        let (d, v) = try await (det, vids)
        let trailer = (v.results ?? []).first { raw in
            (raw.site == "YouTube") && (raw.type == "Trailer" || raw.type == "Teaser")
        }
        return Details(
            trailerUrl: trailer?.key.map { "https://www.youtube.com/watch?v=\($0)" },
            runtime: d.results?.first?.runtime,
            genres: (d.results?.first?.genres ?? []).map(\.name)
        )
    }
}

private extension Data {
    func decode<T: Decodable>() throws -> T {
        try JSONDecoder().decode(T.self, from: self)
    }
}

// MARK: - iTunes (porting di src/logic/itunes.ts)

enum ItunesService {
    private static let base = "https://itunes.apple.com"

    struct ParsedMovie: Identifiable, Equatable {
        var id: Int
        var title: String
        var overview: String
        var posterPath: String?
        var releaseDate: String?
        var previewUrl: String?
        var longDescription: String?
        var genres: [String]
        var runtime: Int?
        var itunesUrl: String?

        var asMovie: Movie {
            Movie(id: id, title: title, overview: overview, posterPath: posterPath,
                  voteAverage: 0, releaseDate: releaseDate)
        }
    }

    private struct Raw: Decodable {
        var trackId: Int?
        var trackName: String?
        var artworkUrl100: String?
        var previewUrl: String?
        var longDescription: String?
        var shortDescription: String?
        var primaryGenreName: String?
        var releaseDate: String?
        var trackViewUrl: String?
        var trackTimeMillis: Int?
        var kind: String?
    }

    private static func toMovie(_ r: Raw) -> ParsedMovie {
        let poster = (r.artworkUrl100 ?? "")
            .replacingOccurrences(of: "/100x100bb.", with: "/600x600bb.")
        return ParsedMovie(
            id: r.trackId ?? 0,
            title: r.trackName ?? "—",
            overview: r.shortDescription ?? String(r.longDescription?.prefix(200) ?? ""),
            posterPath: poster.isEmpty ? nil : poster,
            releaseDate: r.releaseDate,
            previewUrl: r.previewUrl,
            longDescription: r.longDescription,
            genres: r.primaryGenreName.map { [$0] } ?? [],
            runtime: r.trackTimeMillis.map { $0 / 60_000 },
            itunesUrl: r.trackViewUrl
        )
    }

    private static func search(_ term: String, limit: Int, country: String = "it") async throws -> [ParsedMovie] {
        var comps = URLComponents(string: "\(base)/search")
        comps?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "media", value: "movie"),
            URLQueryItem(name: "entity", value: "movie"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: comps!.url!))
        struct Resp: Decodable { var results: [Raw]? }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        return (resp.results ?? [])
            .filter { $0.trackName != nil && $0.artworkUrl100 != nil && $0.kind == "feature-movie" }
            .map(toMovie)
    }

    /// Film disponibili sullo store italiano (novità in ordine di rilascio).
    static func fetchMovies(country: String = "it") async throws -> [ParsedMovie] {
        try await search("film", limit: 48, country: country)
    }

    /// Ricerca per titolo (usata anche dalla ricerca in-app).
    static func searchMovies(_ term: String, country: String = "it") async throws -> [ParsedMovie] {
        try await search(term, limit: 24, country: country)
    }

    /// "Nuovi arrivi": feed RSS pubblico di Apple + lookup in blocco.
    static func fetchNewReleases(country: String = "it") async -> [ParsedMovie] {
        struct Feed: Decodable { var results: [FeedItem]? }
        struct FeedItem: Decodable { var id: String? }
        guard let url = URL(string: "https://rss.applemarketingtools.com/api/v2/\(country)/movies/top/new/all/25.json"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let feed = try? JSONDecoder().decode(Feed.self, from: data),
              let ids = feed.results?.compactMap(\.id), !ids.isEmpty
        else { return [] }
        guard let lurl = URL(string: "\(base)/lookup?id=\(ids.joined(separator: ","))&country=\(country)"),
              let (ldata, _) = try? await URLSession.shared.data(from: lurl),
              let look = try? JSONDecoder().decode([String: [Raw]].self, from: ldata),
              let raws = look["results"]
        else { return [] }
        return raws.filter { $0.trackName != nil }.map(toMovie)
    }

    private static let stopWords: Set<String> = [
        "trailer", "teaser", "ufficiale", "anticipazioni", "trama", "cast",
        "prevendite", "prevendita", "biglietti", "dal", "cinema", "video", "clip",
        "esclusiva", "anteprima", "primissimo", "primissima", "svelato",
    ]
    private static let itArticles = /^(il|lo|la|gli|le|un|una|di|da|che|per|con|su|in|del|della|dei|delle|al|alla|ai|agli|e|ed)$/

    /// Cerca il film citato in una notizia (query progressive 4→3→2 parole).
    static func findMovieFromNewsTitle(_ rawTitle: String, country: String = "it") async -> ParsedMovie? {
        let cleaned = rawTitle.lowercased()
            .replacingOccurrences(of: "[^a-zàèéìòù0-9\\s:]", with: " ", options: .regularExpression)
        let digits = /^[0-9]+$/
        let articles = /^(il|lo|la|gli|le|un|una|di|da|che|per|con|su|in|del|della|dei|delle|al|alla|ai|agli|e|ed)$/
        let tokens = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
            .filter { w in
                w.count >= 3
                    && !stopWords.contains(w)
                    && digits.wholeMatch(in: w) == nil
                    && articles.wholeMatch(in: w) == nil
            }
        guard !tokens.isEmpty else { return nil }

        var queries: [String] = []
        let maxLen = min(4, tokens.count)
        if maxLen >= 2 {
            for len in stride(from: maxLen, through: 2, by: -1) {
                queries.append(tokens.prefix(len).joined(separator: " "))
            }
        }

        for q in queries {
            guard let results = try? await searchMovies(q, country: country), !results.isEmpty else { continue }
            let qWords = q.split(separator: " ").map(String.init)
            if let hit = results.first(where: { m in
                let title = m.title.lowercased()
                return qWords.allSatisfy { title.contains($0) }
            }) {
                return hit
            }
        }
        return nil
    }
}
