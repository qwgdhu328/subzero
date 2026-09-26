import SwiftUI

/// Tab "Oggi": notizie editoriali con righe compatte, filtri e pill nuove.
struct TodayView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var sourceFilter: String? = nil
    @State private var aiOnly = false
    @State private var path = NavigationPath()

    private var sourceNames: [String] {
        Array(Set(app.newsItems.map(\.source))).sorted()
    }

    private var visible: [NewsItem] {
        var list = app.newsItems
        if let f = sourceFilter { list = list.filter { $0.source == f } }
        if aiOnly { list = list.filter { app.aiArticles[$0.id] != nil } }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.count >= 2 {
            list = list.filter { $0.title.lowercased().contains(q) || $0.summary.lowercased().contains(q) }
        }
        return list
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.bg.ignoresSafeArea()
                List {
                    Group {
                        header
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        ForEach(visible) { item in
                            NavigationLink(value: item) {
                                NewsRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                        if visible.isEmpty {
                            emptyState
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                        }
                    }
                    .background(Theme.bg)
                    .listRowBackground(Theme.bg)
                }
                .listStyle(.plain)
                .refreshable { await app.refreshNews() }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: NewsItem.self) { item in
                ArticleView(item: item)
            }
            .navigationDestination(for: DetailRoute.self) { route in
                route.destination
            }
        }
        .task {
            if app.newsItems.isEmpty { await app.refreshNews(silent: true) }
            await app.ensureAiArticles()
            app.startPolling()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(
                eyebrow: "CineFlash · \(todayItalian())",
                title: "Notizie",
                right: HStack(spacing: 8) {
                    if app.newCount > 0 {
                        Button(action: app.showNew) {
                            Text("\(app.newCount) nuove")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Theme.onAccent)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(Capsule().fill(Theme.accent))
                        }
                    }
                    NavigationLink(value: DetailRoute.saved) {
                        ZStack(alignment: .topTrailing) {
                            Text("🔖").font(.system(size: 12))
                            if !app.savedNews.isEmpty {
                                Circle().fill(Theme.accent).frame(width: 8, height: 8).offset(x: 3, y: -3)
                            }
                        }
                        .frame(width: 30, height: 30)
                        .background(Theme.surfaceAlt.cornerRadius(15))
                        .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                    }
                })

            HStack(spacing: 8) {
                InputField(placeholder: "Cerca…", value: $query)
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Text("✕").font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.textDim)
                            .frame(width: 34, height: 34)
                            .background(Theme.surfaceAlt.cornerRadius(17))
                            .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                    }
                }
            }

            HStack(spacing: 10) {
                NavigationLink(value: DetailRoute.presale) {
                    EntryCard(icon: "🎟️", label: "Prevendite", count: app.newsItems.filter(NewsService.isPreSale).count)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                NavigationLink(value: DetailRoute.upcoming) {
                    EntryCard(icon: "📅", label: "In arrivo", count: app.newsItems.filter { !NewsService.isPreSale($0) && NewsService.isUpcoming($0) }.count)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(label: "Tutte", active: sourceFilter == nil) { sourceFilter = nil }
                    ForEach(sourceNames, id: \.self) { name in
                        FilterChip(label: name, active: sourceFilter == name) { sourceFilter = name }
                    }
                    FilterChip(label: "✨ Solo AI", active: aiOnly) { aiOnly.toggle() }
                }
                .padding(.trailing, Theme.pad)
            }

            if let err = app.newsError {
                Text(err)
                    .font(Theme.ui(12))
                    .foregroundColor(Theme.warn)
            }

            // Indicatore di caricamento durante l'aggiornamento (anche silenzioso)
            if app.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView().tint(Theme.accent).scaleEffect(0.7)
                    Text("Aggiorno le notizie…")
                        .font(Theme.ui(11, .semibold))
                        .foregroundColor(Theme.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if app.newsLoading && app.newsItems.isEmpty {
                VStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
                }
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                EmptyStateView(icon: "🔍", title: "Nessun risultato", subtitle: "Prova con parole diverse.")
            } else if sourceFilter != nil {
                EmptyStateView(icon: "📰", title: "Niente da \(sourceFilter ?? "")", subtitle: "Questa testata non ha notizie in cache: prova “Tutte” o un'altra fonte.")
            } else {
                EmptyStateView(icon: "🍿", title: "Nessuna notizia", subtitle: "Controlla la connessione o abilita altre fonti.")
            }
        }
        .padding(.top, 40)
    }
}

// MARK: - Route per la navigazione

enum DetailRoute: Hashable {
    case saved
    case settings
    case presale
    case upcoming
    case permissions
    case privacy
    case aiDashboard
    case aiChat(mode: String, title: String, text: String, source: String)

    @ViewBuilder
    var destination: some View {
        switch self {
        case .saved: SavedView()
        case .settings: SettingsView()
        case .presale: PresaleView()
        case .upcoming: UpcomingView()
        case .permissions: PermissionsView()
        case .privacy: PrivacyView()
        case .aiDashboard: AIDashboardView()
        case .aiChat(let mode, let title, let text, let source):
            AIChatView(mode: mode, ctxTitle: title, ctxText: text, ctxSource: source)
        }
    }
}

// MARK: - Righe e componenti locali

struct NewsRow: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openURL) private var openURL
    let item: NewsItem

    private var ai: AiArticle? { app.aiArticles[item.id] }
    private var isNew: Bool { app.newIds.contains(item.id) }
    private var saved: Bool { app.isSaved(item.id) }
    private var read: Bool { app.readIds.contains(item.id) }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            AsyncImage(url: (item.imageUrl ?? ai?.images.first).flatMap({ URL(string: $0) })) { phase in
                if let img = phase.image {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack { Theme.surfaceAlt; Text("🎬").font(.system(size: 17)) }
                }
            }
            .frame(width: 72, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if ai != nil { Badge(label: "AI", tone: Theme.accent) }
                    if isNew { Badge(label: "NUOVO", tone: Theme.warn) }
                    Text(item.source.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .kerning(0.8)
                        .foregroundColor(Theme.accent)
                        .lineLimit(1)
                    Spacer()
                    Text(NewsService.timeAgo(item.publishedAt))
                        .font(Theme.ui(11))
                        .foregroundColor(Theme.textDim)
                }
                Text(ai?.title ?? item.title)
                    .font(Theme.ui(15, read ? .medium : .semibold))
                    .foregroundColor(read ? Theme.textDim : Theme.text)
                    .lineLimit(2)
                if saved {
                    Text("salvato")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.ok)
                }
            }

            Button(action: { app.markRead(item.id) }) {
                Text("✨").font(.system(size: 12))
                    .frame(width: 30, height: 30)
                    .background(Theme.surfaceAlt.cornerRadius(15))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button(action: { _ = app.toggleSaved(item) }) {
                Text(saved ? "✓" : "＋").font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textDim)
                    .frame(width: 30, height: 30)
                    .background(Theme.surfaceAlt.cornerRadius(15))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }
        .contentShape(Rectangle())
        .contextMenu {
            Button(saved ? "Rimuovi dai salvati" : "Salva") { _ = app.toggleSaved(item) }
        }
    }
}

struct EntryCard: View {
    let icon: String
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 9) {
            Text(icon).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.5)
                    .foregroundColor(Theme.textDim)
                Text(count > 0 ? "\(count)" : "—")
                    .font(Theme.serif(18, .bold))
                    .foregroundColor(Theme.text)
            }
            Spacer()
            Text("›")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(Theme.textDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surface.cornerRadius(Theme.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).stroke(Theme.border, lineWidth: 0.5))
    }
}

struct FilterChip: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.ui(12, active ? .bold : .semibold))
                .foregroundColor(active ? Theme.onAccent : Theme.textDim)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(active ? Theme.text : Theme.surfaceAlt))
                .overlay(Capsule().stroke(active ? Theme.text : Theme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct SkeletonRow: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.surfaceAlt.opacity(pulsing ? 0.5 : 1))
                .frame(width: 72, height: 52)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 5).fill(Theme.surfaceAlt.opacity(pulsing ? 0.5 : 1))
                    .frame(width: 260, height: 10)
                RoundedRectangle(cornerRadius: 5).fill(Theme.surfaceAlt.opacity(pulsing ? 0.5 : 1))
                    .frame(width: 160, height: 10)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}
