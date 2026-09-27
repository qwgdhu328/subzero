import WidgetKit
import SwiftUI

// MARK: - Widget home screen: ultime notizie di cinema

/// Il widget scarica da solo i feed RSS (nessun app group necessario:
/// funziona anche nelle build unsigned firmate con Sideloadly) e mostra
/// i titoli più recenti. Refresh ogni 30 minuti (budget WidgetKit).

struct NewsEntry: TimelineEntry {
    var date: Date
    var items: [WidgetNewsItem]
    var isError: Bool
}

struct NewsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NewsEntry {
        NewsEntry(date: Date(), items: Self.demoItems, isError: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (NewsEntry) -> Void) {
        if context.isPreview {
            completion(NewsEntry(date: Date(), items: Self.demoItems, isError: false))
            return
        }
        Task {
            let items = await Self.fetchLatest()
            completion(NewsEntry(date: Date(), items: items, isError: items.isEmpty))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NewsEntry>) -> Void) {
        Task {
            let items = await Self.fetchLatest()
            let entry = NewsEntry(date: Date(), items: items, isError: items.isEmpty)
            // Prossimo refresh tra 30 minuti
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    static let demoItems: [WidgetNewsItem] = [
        WidgetNewsItem(id: "1", title: "Il nuovo film di Sorrentino apre la stagione", source: "ANSA"),
        WidgetNewsItem(id: "2", title: "Prevendite aperte per il festival", source: "BadTaste"),
        WidgetNewsItem(id: "3", title: "Arriva il sequel più atteso dell'anno", source: "ComingSoon"),
    ]

    /// Scarica i feed (i primi 3 predefiniti) e restituisce le 6 notizie più recenti.
    static func fetchLatest() async -> [WidgetNewsItem] {
        let feeds = [
            ("https://www.ansa.it/sito/notizie/cultura/cinema/cinema_rss.xml", "ANSA"),
            ("https://www.badtaste.it/feed", "BadTaste"),
            ("https://www.cineblog.it/feed", "CineBlog"),
        ]
        var all: [WidgetNewsItem] = []
        await withTaskGroup(of: [WidgetNewsItem].self) { group in
            for (url, name) in feeds {
                group.addTask {
                    guard let u = URL(string: url),
                          let data = try? await Self.fetchFeed(u) else { return [] }
                    return WidgetFeedParser.parse(data, source: name)
                }
            }
            for await items in group { all.append(contentsOf: items) }
        }
        return Array(all.sorted { $0.id > $1.id }.prefix(6))
    }

    /// Limita i byte ricevuti anche senza Content-Length (o con risposta compressa).
    private static func fetchFeed(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              response.expectedContentLength <= Int64(WidgetFeedParser.maxFeedBytes) else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < WidgetFeedParser.maxFeedBytes else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            data.append(byte)
        }
        return data
    }
}

// MARK: - Viste

struct NewsWidgetView: View {
    var entry: NewsEntry

    var body: some View {
        Group {
            if entry.isError || entry.items.isEmpty {
                errorView
            } else {
                listContent
            }
        }
        .containerBackgroundCompat()
        .widgetURL(URL(string: "cineflash://news"))
    }

    private var listContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(Color(hexValue: 0xC93B2F)).frame(width: 8, height: 8)
                Text("CINEFLASH")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.2)
                    .foregroundColor(Color(hexValue: 0xC93B2F))
                Spacer()
                Text("notizie")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hexValue: 0x77726A))
            }
            .padding(.bottom, 8)

            ForEach(entry.items.prefix(4)) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hexValue: 0x191817))
                        .lineLimit(2)
                    Text(item.source.uppercased())
                        .font(.system(size: 8, weight: .heavy))
                        .kerning(0.8)
                        .foregroundColor(Color(hexValue: 0xC93B2F))
                }
                .padding(.vertical, 4)
                if item.id != entry.items.prefix(4).last?.id {
                    Divider()
                        .overlay(Color(hexValue: 0xDDD8CC))
                }
            }
        }
    }

    private var errorView: some View {
        VStack(spacing: 6) {
            Text("🍿").font(.system(size: 24))
            Text("Nessuna notizia")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(hexValue: 0x191817))
            Text("Apri l'app per aggiornare i feed.")
                .font(.system(size: 11))
                .foregroundColor(Color(hexValue: 0x77726A))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Compat iOS 17 containerBackground / iOS 16 fallback.
extension View {
    @ViewBuilder
    func containerBackgroundCompat() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                Color(hexValue: 0xF4F1EA)
            }
        } else {
            background(Color(hexValue: 0xF4F1EA))
        }
    }
}

// MARK: - Widget configuration

struct LatestNewsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CineFlashLatestNews", provider: NewsTimelineProvider()) { entry in
            NewsWidgetView(entry: entry)
        }
        .configurationDisplayName("Ultime notizie")
        .description("I titoli più recenti dalle testate di cinema.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
