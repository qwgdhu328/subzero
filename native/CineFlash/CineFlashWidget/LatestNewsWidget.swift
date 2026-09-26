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

struct WidgetNewsItem: Identifiable {
    var id: String
    var title: String
    var source: String
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
                          let (data, _) = try? await URLSession.shared.data(from: u),
                          let xml = String(data: data, encoding: .utf8) else { return [] }
                    return Self.parseTitles(xml, source: name)
                }
            }
            for await items in group { all.append(contentsOf: items) }
        }
        return Array(all.sorted { $0.id > $1.id }.prefix(6))
    }

    /// Estrae titoli e link dal feed: l'id è l'hash del link (ordina in modo stabile).
    static func parseTitles(_ xml: String, source: String) -> [WidgetNewsItem] {
        var out: [WidgetNewsItem] = []
        guard let itemRe = try? NSRegularExpression(
            pattern: "<(item|entry)(?:\\s[^>]*)?>([\\s\\S]*?)</\\1>", options: [.caseInsensitive]) else { return [] }
        let ns = itemRe.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        for m in ns.prefix(10) {
            guard m.numberOfRanges > 2, let br = Range(m.range(at: 2), in: xml) else { continue }
            let block = String(xml[br])
            let title = Self.firstTagContent(block, tag: "title")
            let link = Self.firstTagContent(block, tag: "link")
                ?? Self.firstAttr(block, tag: "link", attr: "href")
                ?? Self.firstTagContent(block, tag: "guid")
            guard let title, !title.isEmpty else { continue }
            let id = Self.hashId(link ?? title)
            out.append(WidgetNewsItem(id: id, title: title, source: source))
        }
        return out
    }

    static func firstTagContent(_ xml: String, tag: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: "<\(tag)(?:\\s[^>]*)?>([\\s\\S]*?)</\(tag)>", options: [.caseInsensitive]) else { return nil }
        guard let m = re.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: xml) else { return nil }
        var s = String(xml[r])
        s = s.replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return s
    }

    static func firstAttr(_ xml: String, tag: String, attr: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: "<\(tag)\\b[^>]*\\b\(attr)=[\"']([^\"']+)[\"'][^>]*>", options: [.caseInsensitive]) else { return nil }
        guard let m = re.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: xml) else { return nil }
        return String(xml[r])
    }

    static func hashId(_ s: String) -> String {
        var h: Int = 5381
        for ch in s.unicodeScalars { h = ((h << 5) &+ h &+ Int(ch.value)) & 0x7FFFFFFF }
        return String(h, radix: 36)
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
