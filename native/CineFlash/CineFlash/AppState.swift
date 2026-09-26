import SwiftUI
import Combine

/// Stato condiviso dell'app (equivalente di StoreContext + liveNews).
@MainActor
final class AppState: ObservableObject {
    @Published var settings: Settings
    @Published var savedNews: [SavedNewsEntry] = []
    @Published var watchlist: [WatchlistEntry] = []
    @Published var reminders: [ReleaseReminder] = []
    @Published var newsItems: [NewsItem] = []
    @Published var newsLoading = true
    @Published var newsError: String?
    @Published var aiArticles: [String: AiArticle] = [:]
    @Published var readIds: Set<String> = []
    @Published var newIds: Set<String> = []
    @Published var newCount = 0

    private var pollTimer: Timer?

    init() {
        self.settings = Store.loadSettings()
        self.savedNews = Store.loadSavedNews()
        self.watchlist = Store.loadWatchlist()
        self.reminders = Store.loadReminders()
        self.aiArticles = Store.loadAiArticles()
        self.readIds = Set(Store.loadReadHistory())
        if let cached = Store.loadNewsCache(), !cached.items.isEmpty {
            self.newsItems = cached.items
            self.newsLoading = false
        }
    }

    func save() { Store.saveSettings(settings) }

    func update(_ patch: (inout Settings) -> Void) {
        patch(&settings)
        save()
    }

    // MARK: Notizie

    func activeSources() -> [NewsSource] { Store.activeSources(settings) }

    func refreshNews(silent: Bool = false) async {
        if !silent { newsLoading = true }
        newsError = nil
        let sources = activeSources()
        let (items, failed) = await NewsService.fetchAllNews(sources: sources)

        let oldIds = Set(newsItems.map(\.id))
        let fresh = items.filter { x in
            guard !oldIds.contains(x.id), let pub = x.publishedAt,
                  let d = ISO8601DateFormatter().date(from: pub) else { return false }
            return Date().timeIntervalSince(d) <= 600
        }

        if !items.isEmpty {
            newsItems = items
            Store.saveNewsCache(Store.NewsCache(fetchedAt: Date(), items: items))
        }
        if !fresh.isEmpty {
            newIds.formUnion(fresh.map(\.id))
            newCount += fresh.count
            updateLiveActivity(fresh: fresh)
        }
        if !failed.isEmpty && newsItems.isEmpty {
            newsError = "Nessun feed raggiungibile (\(failed.joined(separator: ", ")))."
        } else if !failed.isEmpty {
            newsError = "Alcune fonti non rispondono: \(failed.joined(separator: ", "))."
        }
        newsLoading = false
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshNews(silent: true)
            }
        }
    }

    func showNew() {
        newCount = 0
        newIds = []
        NewsActivityManager.shared.endAll()
    }

    /// Aggiorna l'Isola Dinamica con l'ultima novità (prevendite prioritarie).
    private func updateLiveActivity(fresh: [NewsItem]) {
        let presales = fresh.filter(NewsService.isPreSale)
        let latest = presales.first ?? fresh.first
        guard let item = latest else { return }
        let isPresale = presales.contains(where: { $0.id == item.id })
        let detail: String
        if fresh.count == 1 {
            detail = item.source
        } else {
            detail = "\(fresh.count) novità · ultima da \(item.source)"
        }
        NewsActivityManager.shared.showNews(
            emoji: isPresale ? "🎟️" : "📰",
            headline: item.title,
            detail: detail,
            newCount: newCount
        )
    }

    // MARK: AI redazione (coda a concorrenza limitata)

    private var aiInFlight = Set<String>()

    func ensureAiArticles(limit: Int = 12, concurrency: Int = 3) async {
        guard !newsItems.isEmpty else { return }
        let pending = newsItems.prefix(limit).filter {
            !aiArticles.keys.contains($0.id) && !aiInFlight.contains($0.id)
        }
        guard !pending.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for item in pending.prefix(concurrency) {
                aiInFlight.insert(item.id)
                group.addTask { [weak self] in
                    if let art = await AIService.rewriteArticle(item) {
                        await MainActor.run {
                            self?.aiArticles[art.id] = art
                            Store.saveAiArticle(art)
                        }
                    }
                    await MainActor.run {
                        self?.aiInFlight.remove(item.id)
                    }
                }
            }
            await group.waitForAll()
        }

        // Seconda ondata se ci sono ancora titoli in attesa
        let stillPending = newsItems.prefix(limit).filter {
            !aiArticles.keys.contains($0.id) && !aiInFlight.contains($0.id)
        }
        await withTaskGroup(of: Void.self) { group in
            for item in stillPending {
                aiInFlight.insert(item.id)
                group.addTask { [weak self] in
                    if let art = await AIService.rewriteArticle(item) {
                        await MainActor.run {
                            self?.aiArticles[art.id] = art
                            Store.saveAiArticle(art)
                        }
                    }
                    await MainActor.run {
                        self?.aiInFlight.remove(item.id)
                    }
                }
            }
            await group.waitForAll()
        }
    }

    // MARK: Collezioni

    func toggleSaved(_ item: NewsItem) -> Bool {
        let added = Store.toggleSaved(item)
        savedNews = Store.loadSavedNews()
        return added
    }

    func isSaved(_ id: String) -> Bool { savedNews.contains { $0.id == id } }

    func toggleWatchlist(_ entry: WatchlistEntry) -> Bool {
        let added = Store.toggleWatchlist(entry)
        watchlist = Store.loadWatchlist()
        return added
    }

    func isInWatchlist(_ id: Int) -> Bool { watchlist.contains { $0.id == String(id) } }

    func toggleReminder(_ r: ReleaseReminder) -> Bool {
        let added = Store.toggleReminder(r)
        reminders = Store.loadReminders()
        return added
    }

    func hasReminder(_ movieId: Int) -> Bool { reminders.contains { $0.movieId == String(movieId) } }

    func markRead(_ id: String) {
        Store.markRead(id)
        readIds = Set(Store.loadReadHistory())
    }
}
