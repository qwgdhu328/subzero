import Foundation

// MARK: - News RSS (porting di src/logic/news.ts + alerts.ts)

enum NewsService {
    /// Retry con backoff semplice: 2 tentativi extra.
    private static func fetchText(_ url: String, retries: Int = 2) async throws -> String {
        var lastError: Error?
        for attempt in 0...retries {
            do {
                var req = URLRequest(url: URL(string: url)!)
                req.setValue("CineFlash/2.0 (app; usage: news reader)", forHTTPHeaderField: "User-Agent")
                req.setValue("application/rss+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
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
        let map = ["&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&nbsp;": " ", "&amp;": "&"]
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        if let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
            // Decodifica i riferimenti numerici con un eval manuale
            out = decodeNumericEntities(out)
        }
        out = out.replacingOccurrences(of: "<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>", with: "$1", options: .regularExpression)
        return out
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
    }

    private static func decodeNumericEntities(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else { return s }
        var result = s
        let matches = re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed()
        for m in matches {
            guard let full = Range(m.range, in: s) else { continue }
            let hexPart = m.numberOfRanges > 2 ? Range(m.range(at: 1), in: s).map { String(s[$0]) } : nil
            let numPart = m.numberOfRanges > 2 ? Range(m.range(at: 2), in: s).map { String(s[$0]) } : nil
            var replacement = m.isEmpty ? "" : ""
            if let hex = hexPart, let num = numPart, !num.isEmpty {
                if let c = UInt32(num, radix: hex.isEmpty ? 10 : 16), let scalar = Unicode.Scalar(c) {
                    replacement = String(Character(scalar))
                }
            }
            result.replaceSubrange(full, with: replacement)
        }
        return result
    }

    private static func firstTag(_ xml: String, _ tag: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: "<\(tag)(?:\\s[^>]*)?>([\\s\\S]*?)</\(tag)>", options: [.caseInsensitive]) else { return nil }
        guard let m = re.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: xml) else { return nil }
        return decodeEntities(String(xml[r])).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstAttr(_ xml: String, _ tag: String, _ attr: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: "<\(tag)\\b[^>]*\\b\(attr)=[\"']([^\"']+)[\"'][^>]*>", options: [.caseInsensitive]) else { return nil }
        guard let m = re.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: xml) else { return nil }
        return decodeEntities(String(xml[r]))
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
        let formats = [""]
        _ = formats
        let parsers: [(String, DateFormatter)] = [
            ("rfc", {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "E, d MMM yyyy HH:mm:ss Z"
                return f
            }()),
            ("rfc2", {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "E, d MMM yyyy HH:mm:ss zzz"
                return f
            }()),
        ]
        for (_, f) in parsers {
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

    private static func parseRss(_ xml: String, source: NewsSource) -> [NewsItem] {
        var items: [NewsItem] = []
        guard let itemRe = try? NSRegularExpression(
            pattern: "<(item|entry)(?:\\s[^>]*)?>([\\s\\S]*?)</\\1>", options: [.caseInsensitive]) else { return [] }
        let ns = itemRe.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        for m in ns {
            guard m.numberOfRanges > 2, let br = Range(m.range(at: 2), in: xml) else { continue }
            let block = String(xml[br])

            let title = firstTag(block, "title")
            let linkRaw = firstTag(block, "link")
                ?? firstAttr(block, "link", "href")
                ?? firstTag(block, "guid")
            let summaryRaw = firstTag(block, "description")
                ?? firstTag(block, "summary")
                ?? firstTag(block, "content:encoded")
            let dateRaw = firstTag(block, "pubDate")
                ?? firstTag(block, "published")
                ?? firstTag(block, "updated")
                ?? firstTag(block, "dc:date")
            let img = firstAttr(block, "media:thumbnail", "url")
                ?? firstAttr(block, "media:content", "url")
                ?? firstAttr(block, "enclosure", "url")
                ?? firstAttr(block, "itunes:image", "href")

            guard let title, let linkRaw else { continue }
            items.append(NewsItem(
                id: hashId(linkRaw),
                title: stripHtml(title),
                link: linkRaw.trimmingCharacters(in: .whitespacesAndNewlines),
                source: source.name,
                sourceKey: source.key,
                summary: summaryRaw.map { String(stripHtml($0).prefix(400)) } ?? "",
                publishedAt: parseDate(dateRaw),
                imageUrl: img
            ))
        }
        return items
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
        deduped.sort { a, b in
            let ta = a.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }?.timeIntervalSince1970 ?? 0
            let tb = b.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }?.timeIntervalSince1970 ?? 0
            return ta > tb
        }
        return (deduped, failed)
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
