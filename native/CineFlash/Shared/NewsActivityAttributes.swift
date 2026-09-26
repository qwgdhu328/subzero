import Foundation
import ActivityKit

/// Attributi della Live Activity di CineFlash: mostrata sull'Isola Dinamica
/// e in schermata di blocco quando arrivano nuove notizie o si aprono
/// prevendite. Compilata sia nell'app sia nell'estensione widget.
public struct NewsActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Emojy del tipo di avviso: 🎟️ prevendite, 📰 notizie.
        public var emoji: String
        /// Titolo della notizia più recente.
        public var headline: String
        /// Riga di contesto (fonte, numero di novità).
        public var detail: String
        /// Numero totale di novità non lette.
        public var newCount: Int
        public var updatedAt: Date

        public init(emoji: String, headline: String, detail: String, newCount: Int, updatedAt: Date) {
            self.emoji = emoji
            self.headline = headline
            self.detail = detail
            self.newCount = newCount
            self.updatedAt = updatedAt
        }
    }

    public init() {}
}
