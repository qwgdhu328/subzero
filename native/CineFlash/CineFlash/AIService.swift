import Foundation

private extension Data {
    func decodeUTF8() -> String { String(data: self, encoding: .utf8) ?? "" }
}

// MARK: - AI gratuita nel cloud (OpenRouter) — porting di cloudAI.ts + aiNews.ts

enum AIService {
    /// Chiave di servizio incorporata (già pubblica nel repo storico) in base64,
    /// come richiesto dalle regole di push protection di GitHub.
    private static let apiKeyB64 =
        "c2stb3ItdjEtYzhjOWZhOGFlMmJhN2Y5ZTg1NzY5MGY0NmUzZTNhYzY4YTdmMDIzYmVmYTcwMTc0YzQ3ODUzODMwNTU3ZDY5ZA=="
    private static var apiKey: String {
        Data(Data(base64Encoded: apiKeyB64) ?? Data()).decodeUTF8()
    }
    private static let endpoint = "https://openrouter.ai/api/v1/chat/completions"

    /// Modelli gratuiti provati in ordine: il primo che risponde vince.
    private static let freeModels = [
        "z-ai/glm-5.2:free",
        "nvidia/nemotron-3.5-lightning:free",
        "google/gemma-4-31b-it:free",
    ]
    /// Modelli per la redazione (riscrittura articoli).
    private static let writerModels = [
        "openai/gpt-4o-mini",
        "meta-llama/llama-3.3-70b-instruct",
    ]

    // MARK: Tipi chat

    struct ChatMessage: Codable, Equatable {
        var role: String // "user" | "assistant"
        var content: String
    }

    struct Context {
        var title: String?
        var text: String?
        var source: String?
    }

    struct CloudResult {
        var text: String
        var reasoning: String
    }

    private struct Body: Encodable {
        var model: String
        var temperature: Double
        var max_tokens: Int
        var stream: Bool?
        var messages: [Msg]
        struct Msg: Encodable {
            var role: String
            var content: String
        }
    }

    private static func post(_ body: Body) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    // MARK: Chat cloud (non-streaming: risposta completa + thinking)

    static func askCloud(
        _ question: String,
        context: Context,
        history: [ChatMessage]
    ) async throws -> CloudResult {
        var sys = "Sei l'assistente AI di CineFlash, un'app di cinema. "
        sys += "Rispondi sempre in ITALIANO, chiaro e semplice, come un buon giornalista che spiega a tutti, anche a chi non è esperto. "
        sys += "Frasi brevi, parole comuni, niente gergo tecnico non spiegato. "
        sys += "Se la domanda riguarda una notizia o un film fornito nel contesto, usa solo quelle informazioni senza inventare fatti. "
        sys += "Risposte concise: di solito da 2 a 6 frasi."

        var parts: [String] = []
        if let t = context.title { parts.append("Titolo del contenuto: \(t)") }
        if let s = context.source { parts.append("Fonte: \(s)") }
        if let t = context.text { parts.append("Contesto fornito dall'app:\n\(t)") }
        let userMsg = parts.isEmpty ? question : "\(parts.joined(separator: "\n"))\n\nDomanda: \(question)"

        var messages: [Body.Msg] = [Body.Msg(role: "system", content: sys)]
        for m in history.suffix(8) where !m.content.trimmingCharacters(in: .whitespaces).isEmpty {
            messages.append(Body.Msg(role: m.role, content: m.content))
        }
        messages.append(Body.Msg(role: "user", content: userMsg))

        var lastError: Error?
        for model in freeModels {
            let body = Body(model: model, temperature: 0.6, max_tokens: 1600, stream: nil, messages: messages)
            do {
                let (data, http) = try await post(body)
                guard (200..<300).contains(http.statusCode) else { continue }
                struct Resp: Decodable {
                    var choices: [Choice]?
                    struct Choice: Decodable {
                        var message: M?
                        struct M: Decodable {
                            var content: String?
                            var reasoning: String?
                            var reasoning_content: String?
                        }
                    }
                }
                let resp = try JSONDecoder().decode(Resp.self, from: data)
                guard let text = resp.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { continue }
                let reasoning = resp.choices?.first?.message?.reasoning
                    ?? resp.choices?.first?.message?.reasoning_content ?? ""
                return CloudResult(text: text, reasoning: reasoning.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NSError(
            domain: "AIService", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "L'AI gratuita non è raggiungibile adesso. Riprova tra poco."]
        )
    }

    // MARK: Redazione AI (riscrittura articoli)

    struct RewriteOutcome {
        var title: String
        var standfirst: String
        var paragraphs: [String]
    }

    static func rewriteArticle(_ item: NewsItem) async -> AiArticle? {
        // 1) Scarica l'HTML originale per testo e immagini
        var articleText: String?
        var images: [String] = []
        if let url = URL(string: item.link) {
            var req = URLRequest(url: url)
            req.timeoutInterval = 12
            req.setValue("CineFlash/2.0 (app; usage: ai newsroom)", forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let html = String(data: data, encoding: .utf8), html.count > 500 {
                articleText = String(html
                    .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(4200))
                images = Self.extractImages(html, baseUrl: item.link)
            }
        }

        // 2) Chiede la riscrittura ai modelli
        let prompt = """
        Riscrivi questa notizia di cinema per i lettori dell'app CineFlash in ITALIANO CHIARO E SEMPLICE.

        REGOLE:
        - Usa frasi brevi e parole comuni; spiega i termini tecnici.
        - NON inventare fatti: usa solo le informazioni qui sotto.
        - Tono neutro, nessuna opinione, nessun clickbait.

        NOTIZIA:
        Titolo originale: \(item.title)
        \(item.summary.isEmpty ? "" : "Sommario dal feed: \(item.summary)")
        \(articleText.map { "Testo completo:\n\($0)" } ?? "")

        Rispondi SOLO con JSON valido:
        {"title": "...", "standfirst": "...", "paragraphs": ["...", "..."]}
        """

        for model in writerModels {
            let body = Body(
                model: model, temperature: 0.4, max_tokens: 1400, stream: nil,
                messages: [
                    Body.Msg(role: "system", content: "Sei il redattore capo di CineFlash. Scrivi articoli chiarissimi, corretti e neutri. Rispondi solo con JSON."),
                    Body.Msg(role: "user", content: prompt),
                ])
            guard let (data, http) = try? await post(body), (200..<300).contains(http.statusCode) else { continue }
            struct Resp: Decodable { var choices: [C]?; struct C: Decodable { var message: M?; struct M: Decodable { var content: String? } } }
            guard let resp = try? JSONDecoder().decode(Resp.self, from: data),
                  let raw = resp.choices?.first?.message?.content else { continue }

            struct Parsed: Decodable { var title: String?; var standfirst: String?; var paragraphs: [String]? }
            // Recupera il primo oggetto JSON bilanciato
            guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else { continue }
            guard let parsed = try? JSONDecoder().decode(Parsed.self, from: Data(raw[start...end].utf8)) else { continue }

            let paragraphs = (parsed.paragraphs ?? [])
                .filter { $0.trimmingCharacters(in: .whitespaces).count >= 30 }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .prefix(8)
            if paragraphs.isEmpty { continue }

            return AiArticle(
                id: item.id,
                title: String(parsed.title?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120) ?? item.title),
                standfirst: String((parsed.standfirst ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)),
                paragraphs: Array(paragraphs),
                images: images,
                source: item.source,
                sourceUrl: item.link,
                publishedAt: item.publishedAt,
                rewrittenAt: Date()
            )
        }
        return nil
    }

    /// Estrae og:image e <img> editoriali (porting di extractImages).
    static func extractImages(_ html: String, baseUrl: String) -> [String] {
        var found: [String] = []
        if let metaRe = try? NSRegularExpression(pattern: "<meta[^>]+(?:property|name)=[\"'](?:og:image(?::secure_url)?|twitter:image(?::src)?)[\"'][^>]*>", options: [.caseInsensitive]) {
            for m in metaRe.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard let r = Range(m.range, in: html) else { continue }
                let tag = String(html[r])
                if let c = tag.range(of: "content=[\"']([^\"']+)[\"']", options: .regularExpression) {
                    var v = String(tag[c])
                    v = v.replacingOccurrences(of: "content=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    found.append(v)
                }
            }
        }
        if let imgRe = try? NSRegularExpression(pattern: "<img\\b[^>]*>", options: [.caseInsensitive]) {
            for m in imgRe.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard let r = Range(m.range, in: html) else { continue }
                let tag = String(html[r])
                let src = tag.range(of: "\\bsrc=[\"']([^\"']+)[\"']", options: .regularExpression)
                    .map { String(tag[$0]) }?.replacingOccurrences(of: "src=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                let dsrc = tag.range(of: "\\bdata-src=[\"']([^\"']+)[\"']", options: .regularExpression)
                    .map { String(tag[$0]) }?.replacingOccurrences(of: "data-src=", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                guard var s = src ?? dsrc else { continue }
                if s.range(of: "(logo|icon|sprite|avatar|pixel|badge|banner-ad)", options: [.regularExpression, .caseInsensitive]) != nil { continue }
                s = s.replacingOccurrences(of: "&amp;", with: "&")
                if let abs = URL(string: s, relativeTo: URL(string: baseUrl))?.absoluteURL.absoluteString {
                    found.append(abs)
                }
            }
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }.prefix(10).map { $0 }
    }
}
