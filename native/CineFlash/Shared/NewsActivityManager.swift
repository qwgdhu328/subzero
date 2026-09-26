import Foundation
import ActivityKit
import SwiftUI
import WidgetKit

/// Gestisce la Live Activity sull'Isola Dinamica (iOS 16.1+):
/// avvio all'arrivo di notizie/prevendite, aggiornamenti, terminazione.
@MainActor
final class NewsActivityManager: ObservableObject {
    static let shared = NewsActivityManager()

    @Published var isSupported: Bool
    @Published var lastError: String?

    /// Durata massima: dopo un'ora la activity si chiude da sola.
    private static let maxDuration: TimeInterval = 3600

    private init() {
        isSupported = ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Avvia (o aggiorna) la Live Activity con le ultime novità.
    func showNews(emoji: String, headline: String, detail: String, newCount: Int) {
        guard isSupported else { return }
        let state = NewsActivityAttributes.ContentState(
            emoji: emoji, headline: headline, detail: detail, newCount: newCount, updatedAt: Date())

        Task {
            do {
                let existing = Activity<NewsActivityAttributes>.activities
                if let current = existing.first {
                    await current.update(using: state)
                } else {
                    let attrs = NewsActivityAttributes()
                    _ = try Activity<NewsActivityAttributes>.request(
                        attributes: attrs,
                        content: .init(state: state, staleDate: Date().addingTimeInterval(Self.maxDuration))
                    )
                }
                lastError = nil
            } catch {
                // Live Activities non disponibili (permesso negato, Limiti, simulatore vecchio…)
                lastError = error.localizedDescription
            }
        }
    }

    /// Stato di caricamento: mostra "Aggiorno i feed…" sull'isola mentre
    /// l'app scarica le notizie. Aggiorna anche i widget home screen.
    func showLoading() {
        guard isSupported else { return }
        let state = NewsActivityAttributes.ContentState(
            emoji: "⏳",
            headline: "Aggiorno i feed…",
            detail: "Controllo le ultime notizie",
            newCount: 0,
            updatedAt: Date())
        Task {
            WidgetCenter.shared.reloadAllTimelines()
            do {
                let existing = Activity<NewsActivityAttributes>.activities
                if let current = existing.first {
                    await current.update(using: state)
                } else {
                    _ = try Activity<NewsActivityAttributes>.request(
                        attributes: NewsActivityAttributes(),
                        content: .init(state: state, staleDate: Date().addingTimeInterval(Self.maxDuration)))
                }
            } catch {
                // best effort
            }
        }
    }

    /// Chiude la Live Activity (es. quando l'utente apre le notizie).
    func endAll() {
        guard isSupported else { return }
        Task {
            for activity in Activity<NewsActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }
}
