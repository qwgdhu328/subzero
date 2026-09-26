import SwiftUI

/// Chat AI (cloud gratuito): messaggi, thinking in diretta, barra input.
struct ChatView: View {
    @State private var messages: [AIService.ChatMessage] = []
    @State private var input = ""
    @State private var streaming = false
    @State private var streamText = ""
    @State private var thinkText = ""
    @State private var error: String?
    var context: AIService.Context
    /// Domanda iniziale inviata automaticamente (dal contesto notizia/film).
    var seed: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    if messages.isEmpty && !streaming {
                        welcome
                    }
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, m in
                        Bubble(role: m.role == "user" ? .user : .ai, text: m.content)
                    }
                    if !thinkText.isEmpty {
                        ThinkingBox(text: thinkText, running: streaming)
                    }
                    if streaming && streamText.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().tint(Theme.accent)
                            Text(thinkText.isEmpty ? "sto pensando…" : "scrivo la risposta…")
                                .font(Theme.ui(13)).foregroundColor(Theme.textDim)
                        }
                    } else if streaming && !streamText.isEmpty {
                        Bubble(role: .ai, text: streamText)
                    }
                    if let e = error {
                        Text(e).font(Theme.ui(12)).foregroundColor(Theme.danger)
                    }
                }
                .padding(Theme.pad)
            }

            inputBar
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiSeed)) { note in
            if let q = note.object as? String { sendSeed(q) }
        }
    }

    private var welcome: some View {
        VStack(spacing: 10) {
            Text("☁️").font(.system(size: 44))
            Text("AI gratuita, sempre pronta")
                .font(Theme.serif(18)).foregroundColor(Theme.text)
            Text("Nessun download, nessuna attesa. Chiedi quello che vuoi sul mondo del cinema.")
                .font(Theme.ui(13)).foregroundColor(Theme.textDim)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            if streaming {
                Button(action: { streaming = false }) {
                    Text("■ Interrompi")
                        .font(Theme.ui(13, .bold)).foregroundColor(Theme.danger)
                        .padding(.vertical, 12).padding(.horizontal, 16)
                        .background(Theme.surfaceAlt.cornerRadius(999))
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            } else {
                InputField(placeholder: "Chiedi…", value: $input)
                    .onSubmit(send)
                Button(action: send) {
                    Text("↑")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Theme.onAccent)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(input.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 1)
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 10)
        .background(Theme.bg)
    }

    private func send() {
        let q = input.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !streaming else { return }
        input = ""
        error = nil
        messages.append(AIService.ChatMessage(role: "user", content: q))
        streaming = true
        streamText = ""
        thinkText = ""
        let history = messages.dropLast().suffix(8)
        Task {
            do {
                let r = try await AIService.askCloud(q, context: context, history: history.map {
                    AIService.ChatMessage(role: $0.role, content: $0.content)
                })
                messages.append(AIService.ChatMessage(role: "assistant", content: r.text))
                thinkText = r.reasoning
            } catch {
                self.error = "Generazione interrotta. Riprova."
            }
            streaming = false
            streamText = ""
        }
    }

    private func sendSeed(_ question: String) {
        guard messages.isEmpty, !streaming else { return }
        input = question
        send()
    }
}

struct Bubble: View {
    enum Role { case user, ai }
    let role: Role
    let text: String

    var body: some View {
        HStack {
            if role == .user { Spacer(minLength: 40) }
            Text(text)
                .font(role == .user ? Theme.ui(15) : Theme.ui(15))
                .foregroundColor(role == .user ? Theme.onAccent : Theme.text)
                .lineSpacing(3)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusMd)
                        .fill(role == .user ? Theme.accent : Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMd)
                        .stroke(role == .user ? .clear : Theme.border, lineWidth: 0.5)
                )
            if role == .ai { Spacer(minLength: 40) }
        }
    }
}

struct ThinkingBox: View {
    let text: String
    var running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(running ? "💭 Sta ragionando…" : "💭 Pensiero")
                    .font(Theme.ui(12, .bold)).foregroundColor(Theme.textDim)
                if running { ProgressView().tint(Theme.textDim).scaleEffect(0.7) }
            }
            Text(text)
                .font(Theme.ui(12)).foregroundColor(Theme.textDim)
                .lineLimit(running ? nil : 3)
                .lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceAlt.opacity(0.6).cornerRadius(Theme.radiusSm))
    }
}

// MARK: - Tab AI

struct AITabView: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ScreenHeader(
                    eyebrow: "CineFlash · AI gratuita",
                    title: "AI",
                    subtitle: "Chiedi alla tua redazione privata: notizie, film, curiosità.")
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(Theme.bg)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }

            ChatView(context: AIService.Context(title: nil, text: nil, source: nil))
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

extension Notification.Name {
    static let aiSeed = Notification.Name("cineflash.aiSeed")
}

// MARK: - Pagina AI con contesto

struct AIChatView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: String
    let ctxTitle: String
    let ctxText: String
    let ctxSource: String?
    @State private var chatKey = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode == "news" ? "NOTIZIA" : "FILM")
                        .font(.system(size: 10, weight: .heavy)).kerning(1)
                        .foregroundColor(Theme.accent)
                    Text(ctxTitle)
                        .font(Theme.ui(14, .bold)).foregroundColor(Theme.text).lineLimit(2)
                }
                Spacer()
                Button(action: { chatKey += 1 }) {
                    Text("↺ Nuova chat")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.surfaceAlt.cornerRadius(999))
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.pad)
            .padding(.vertical, 10)
            .background(Theme.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }

            AIChatContexted(mode: mode, ctxTitle: ctxTitle, ctxText: ctxText, ctxSource: ctxSource)
                .id(chatKey)
                .onAppear { chatKey = 0 }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

/// Chat con invio automatico del primo messaggio guidato.
struct AIChatContexted: View {
    let mode: String
    let ctxTitle: String
    let ctxText: String
    let ctxSource: String?
    @State private var autoSent = false

    var body: some View {
        ChatView(
            context: AIService.Context(title: ctxTitle, text: ctxText, source: ctxSource),
            seed: autoSent ? nil : seedText
        )
        .onAppear {
            if !autoSent && !ctxText.isEmpty {
                autoSent = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .aiSeed, object: seedText)
                }
            }
        }
    }

    private var seedText: String {
        mode == "news"
            ? "Spiegami in parole semplici questa notizia: cosa succede e perché è importante?"
            : "Presentami questo film in modo semplice: di cosa parla la trama e perché vale la pena vederlo?"
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @State private var page = 0

    private let pages: [(icon: String, title: String, body: String)] = [
        ("🎬", "Benvenuto in CineFlash", "Le notizie di cinema delle principali testate italiane, riscritte in modo chiaro dalla redazione AI."),
        ("🎟️", "Prevendite e biglietti", "Ti avvisiamo quando si aprono le prevendite e ti portiamo ai cinema veri della tua città."),
        ("✨", "AI gratuita", "Chiedi qualsiasi cosa sul cinema: l'AI nel cloud risponde subito, senza download."),
    ]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Text(pages[page].icon).font(.system(size: 64))
                Text(pages[page].title)
                    .font(Theme.serif(28)).foregroundColor(Theme.text)
                    .multilineTextAlignment(.center)
                Text(pages[page].body)
                    .font(Theme.ui(15)).foregroundColor(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineSpacing(4)
                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Theme.accent : Theme.surfaceAlt)
                            .frame(width: 8, height: 8)
                    }
                }

                PillButton(label: page < pages.count - 1 ? "Avanti" : "Inizia") {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        app.update { $0.onboarded = true }
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Articolo (lettura con versione AI se disponibile)

struct ArticleView: View {
    let item: NewsItem
    @Environment(\.dismiss) private var dismiss
    @State private var aiArticle: AiArticle?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let ai = aiArticle {
                    AiArticleBody(article: ai)
                } else {
                    OriginalArticleBody(item: item)
                }
            }
            .padding(Theme.pad)
        }
        .background(Theme.bg)
        .navigationTitle(item.source)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            aiArticle = Store.loadAiArticles()[item.id]
        }
    }
}

private struct AiArticleBody: View {
    let article: AiArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let urlString = article.images.first, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Theme.surfaceAlt
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
            }
            Badge(label: "AI · \(article.source)", tone: Theme.accent)
            Text(article.title)
                .font(Theme.serif(24)).foregroundColor(Theme.text)
            Text(article.standfirst)
                .font(Theme.ui(15, .semibold)).foregroundColor(Theme.textDim).lineSpacing(3)
            ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { _, p in
                Text(p).font(Theme.ui(16)).foregroundColor(Theme.text).lineSpacing(6)
            }
            if let src = URL(string: article.sourceUrl) {
                Link("Leggi l'originale su \(article.source) →", destination: src)
                    .font(Theme.ui(13, .bold)).foregroundColor(Theme.accent)
            }
        }
    }
}

private struct OriginalArticleBody: View {
    let item: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.source.uppercased())
                .font(.system(size: 10, weight: .heavy)).kerning(0.8)
                .foregroundColor(Theme.accent)
            Text(item.title).font(Theme.serif(24)).foregroundColor(Theme.text)
            if !item.summary.isEmpty {
                Text(item.summary).font(Theme.ui(16)).foregroundColor(Theme.textDim).lineSpacing(5)
            }
            ProgressView("Carico l'articolo…").tint(Theme.accent).padding(.top, 20)
            if let link = URL(string: item.link) {
                Link("Apri l'articolo originale →", destination: link)
                    .font(Theme.ui(13, .bold)).foregroundColor(Theme.accent)
            }
        }
    }
}
