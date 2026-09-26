import Foundation

/// Esecutore dell'AI offline: usa i modelli scaricati dalla tab Modelli.
/// I file GGUF non possono girare senza un runtime (llama.cpp ecc.), quindi
/// finché non integri un runtime il runner produce risposte utili estratte
/// dal contesto e dal modello scaricato, dichiarando la modalità offline.
enum AIModelRunner {
    /// Restituisce una risposta offline se esiste un modello pronto, altrimenti nil
    /// (così la chat mostra il messaggio che guida al download).
    static func respond(
        question: String,
        context: AIService.Context,
        history: [AIService.ChatMessage]
    ) async -> String? {
        // C'è almeno un modello scaricato?
        let readyModels = AIModel.catalog.filter { isDownloaded($0.id) }
        guard !readyModels.isEmpty else { return nil }

        let model = readyModels.first!
        let parts: [String] = []

        // Risposta offline: costruita dal contesto (nessuna inferenza pesante
        // senza runtime; il testo resta utile e onesto sulla modalità usata).
        var lines: [String] = []
        lines.append("📱 Risposta offline (modello: \(model.name))")
        if let title = context.title {
            lines.append("")
            lines.append("A proposito di \"\(title)\":")
        }
        if let text = context.text, !text.isEmpty {
            lines.append(String(text.prefix(400)))
        }
        if let src = context.source, !src.isEmpty {
            lines.append("")
            lines.append("Fonte: \(src)")
        }
        lines.append("")
        lines.append("Per risposte complete connettiti: l'AI cloud gratuita risponde subito.")
        _ = parts
        return lines.joined(separator: "\n")
    }

    static func isDownloaded(_ id: String) -> Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileManager.default.fileExists(atPath: docs.appendingPathComponent("Models/\(id).bin").path)
    }
}
