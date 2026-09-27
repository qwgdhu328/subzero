import Foundation

// MARK: - News RSS (porting di src/logic/news.ts + alerts.ts)

enum NewsService {
    // Limiti per ogni fonte, prima di decodifica e parsing.
    static let maxFeedBytes = 2 * 1024 * 1024
    private static let maxFieldBytes = 16 * 1024
    private static let maxFeedItems = 512

    /// Retry con backoff semplice: 2 tentativi extra.
    private static func fetchText(_ url: String, retries: Int = 2) async throws -> String {
        var lastError: Error?
        for attempt in 0...retries {
            do {
                var req = URLRequest(url: URL(string: url)!)
                req.setValue("CineFlash/2.0 (app; usage: news reader)", forHTTPHeaderField: "User-Agent")
                req.setValue("application/rss+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
                let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                defer { bytes.task.cancel() }
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                guard resp.expectedContentLength <= Int64(maxFeedBytes) else {
                    throw URLError(.dataLengthExceedsMaximum)
                }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < maxFeedBytes else {
                        throw URLError(.dataLengthExceedsMaximum)
                    }
                    data.append(byte)
                }
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                // Un feed troppo grande non diventa valido con un nuovo tentativo.
                if (error as? URLError)?.code == .dataLengthExceedsMaximum { throw error }
                lastError = error
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: UInt64(400 * (attempt + 1)) * 1_000_000)
                }
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    // MARK: Parsing XML minimale (RSS 2.0 + Atom)

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
        out = out.replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
        return decodeNumericEntities(out)
    }

    /// Decodifica i riferimenti numerici XML: &#8217; e &#x27;.
    private static func decodeNumericEntities(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else { return s }
        var result = s
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let full = Range(m.range, in: s),
                  m.numberOfRanges >= 3,
                  let hexR = Range(m.range(at: 1), in: s),
                  let numR = Range(m.range(at: 2), in: s) else { continue }
            let isHex = !s[hexR].isEmpty
            let numStr = String(s[numR])
            var replacement = ""
            if let c = UInt32(numStr, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(c) {
                replacement = String(Character(scalar))
            }
            result.replaceSubrange(full, with: replacement)
        }
        return result
    }

    private static func stripHtml(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let f1 = DateFormatter()
        f1.locale = Locale(identifier: "en_US_POSIX")
        f1.dateFormat = "E, d MMM yyyy HH:mm:ss Z"
        let f2 = DateFormatter()
        f2.locale = Locale(identifier: "en_US_POSIX")
        f2.dateFormat = "E, d MMM yyyy HH:mm:ss zzz"
        for f in [f1, f2] {
            if let d = f.date(from: raw) {
                return ISO8601DateFormatter().string(from: d)
            }
        }
        if let d = ISO8601DateFormatter().date(from: raw) {
            return ISO8601DateFormatter().string(from: d)
        }
        return nil
    }

    /// id stabile per dedup: hash semplice del link (o del titolo).
    static func hashId(_ s: String) -> String {
        var h: Int = 5381
        for ch in s.unicodeScalars {
            h = ((h << 5) &+ h &+ Int(ch.value)) & 0x7FFFFFFF
        }
        return "n_\(String(h, radix: 36))"
    }

    static func parseRss(_ xml: String, source: NewsSource) -> [NewsItem] {
        // Rifiuta DTD prima del parser, inclusi gli entity interni espandibili.
        guard xml.utf8.count <= maxFeedBytes, !xml.contains("<!DOCTYPE") else { return [] }
        let delegate = FeedParser(source: source)
        let parser = XMLParser(data: Data(xml.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), parser.parserError == nil else { return [] }
        return delegate.items
    }

    /// SAX: avanza una volta nel documento; nessuna ricerca di chiusure ripetuta.
    private final class FeedParser: NSObject, XMLParserDelegate {
        let source: NewsSource
        var items: [NewsItem] = []
        private var depth = 0
        private var itemDepth: Int?
        private var itemCount = 0
        private var field: String?
        private var text = ""
        private var textBytes = 0
        private var fields: [String: String] = [:]
        private var attributes: [String: String] = [:]
        private let textFields: Set<String> = [
            "title", "link", "guid", "description", "summary", "content:encoded",
            "pubdate", "published", "updated", "dc:date"
        ]

        init(source: NewsSource) { self.source = source }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String]) {
            depth += 1
            guard depth <= 64 else { parser.abortParsing(); return }
            let name = elementName.lowercased()
            if itemDepth == nil && (name == "item" || name == "entry") {
                itemCount += 1
                guard itemCount <= maxFeedItems else { parser.abortParsing(); return }
                itemDepth = depth
                fields = [:]
                attributes = [:]
            } else if let itemDepth, depth == itemDepth + 1 {
                if textFields.contains(name), fields[name] == nil {
                    field = name
                    text = ""
                    textBytes = 0
                }
                let attribute: String?
                switch name {
                case "link", "itunes:image": attribute = "href"
                case "media:thumbnail", "media:content", "enclosure": attribute = "url"
                default: attribute = nil
                }
                if let attribute, let value = attributeDict[attribute], attributes[name] == nil {
                    guard value.utf8.count <= maxFieldBytes else { parser.abortParsing(); return }
                    attributes[name] = value
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard field != nil else { return }
            textBytes += string.utf8.count
            guard textBytes <= maxFieldBytes else { parser.abortParsing(); return }
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self))
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            if let itemDepth {
                if depth == itemDepth + 1, let field {
                    fields[field] = decodeEntities(text).trimmingCharacters(in: .whitespacesAndNewlines)
                    self.field = nil
                } else if depth == itemDepth {
                    appendItem()
                    self.itemDepth = nil
                }
            }
            depth -= 1
        }

        private func appendItem() {
            // Atom usa link/@href, RSS usa link o guid.
            let link = fields["link"].flatMap { $0.isEmpty ? nil : $0 }
                ?? attributes["link"] ?? fields["guid"]
            guard let title = fields["title"], let link else { return }
            let summary = fields["description"] ?? fields["summary"] ?? fields["content:encoded"]
            let date = fields["pubdate"] ?? fields["published"] ?? fields["updated"] ?? fields["dc:date"]
            let image = attributes["media:thumbnail"] ?? attributes["media:content"]
                ?? attributes["enclosure"] ?? attributes["itunes:image"]
            items.append(NewsItem(
                id: hashId(link), title: stripHtml(title),
                link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                source: source.name, sourceKey: source.key,
                summary: summary.map { String(stripHtml($0).prefix(400)) } ?? "",
                publishedAt: parseDate(date), imageUrl: image
            ))
        }
    }

    /// Carica più feed in parallelo; i falliti vengono saltati.
    static func fetchAllNews(sources: [NewsSource]) async -> (items: [NewsItem], failed: [String]) {
        let results = await withTaskGroup(of: (Int, [NewsItem]?).self) { group in
            for (i, src) in sources.enumerated() {
                group.addTask {
                    do {
                        let xml = try await fetchText(src.url)
                        let parsed = parseRss(xml, source: src)
                        return parsed.isEmpty ? (i, nil) : (i, parsed)
                    } catch {
                        return (i, nil)
                    }
                }
            }
            var out: [Int: [NewsItem]] = [:]
            for await (i, items) in group { out[i] = items }
            return out
        }

        var failed: [String] = []
        var all: [NewsItem] = []
        for (i, src) in sources.enumerated() {
            if let items = results[i] {
                all.append(contentsOf: items)
            } else {
                failed.append(src.name)
            }
        }

        var seen = Set<String>()
        let deduped = all.filter { seen.insert($0.id).inserted }
        let sortedItems = deduped.sorted { a, b in
            let ta = a.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }?.timeIntervalSince1970 ?? 0
            let tb = b.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }?.timeIntervalSince1970 ?? 0
            return ta > tb
        }
        return (sortedItems, failed)
    }

    // MARK: Avvisi (porting di alerts.ts)

    static let prevenditeRe = "\\b(prevendit[ae]|bigliett[oi]\\s+(?:in\\s+)?(?:vendita|disponibili)|anticipazioni?|anteprima(?:\\s+vendita)?|earl[xy]\\s+access|oversale|primissime)\\b"
    static let inArrivoRe = "\\b(in\\s+arrivo|arriva(?:rà|no)?|esce\\s+(?:il|ne[lL]la?)|uscita\\s+(?:al\\s+cinema|italiana|nelle\\s+sale)|nelle?\\s+sale|data\\s+di\\s+uscita|nuovo\\s+film|nuova\\s+pellicola|arriverà|debutta|esordisce|trailer\\s+ufficiale|teaser\\s+ufficiale)\\b"

    static func isPreSale(_ item: NewsItem) -> Bool {
        let text = "\(item.title) \(item.summary)"
        return text.range(of: prevenditeRe, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isUpcoming(_ item: NewsItem) -> Bool {
        let text = "\(item.title) \(item.summary)"
        return text.range(of: inArrivoRe, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Testo articolo (per contesto AI)

    static func fetchArticleText(_ url: String, maxChars: Int = 3500) async -> String? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.setValue("CineFlash/2.0 (app; usage: ai context)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else { return nil }
        let text = html
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<nav[\\s\\S]*?</nav>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<header[\\s\\S]*?</header>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<footer[\\s\\S]*?</footer>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 80 ? String(text.prefix(maxChars)) : nil
    }

    /// "5 min", "2 ore", "3 giorni", "12 set"…
    static func timeAgo(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "" }
        let diff = Date().timeIntervalSince(d)
        if diff < 0 { return "" }
        let min = Int(diff / 60)
        if min < 1 { return "adesso" }
        if min < 60 { return "\(min) min" }
        let h = min / 60
        if h < 24 { return h == 1 ? "1 ora" : "\(h) ore" }
        let dd = h / 24
        if dd < 7 { return dd == 1 ? "1 giorno" : "\(dd) giorni" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }
}
