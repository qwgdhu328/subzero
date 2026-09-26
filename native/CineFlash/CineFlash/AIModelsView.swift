import SwiftUI
import Combine

/// Un modello AI scaricabile localmente (per funzioni offline come riassunti,
/// riconoscimento, OCR di locandine ecc.). Lo scaricamento usa URLSession
/// con progressione visibile; i modelli vivono in Documents/Models.
struct AIModel: Identifiable, Equatable {
    var id: String
    var name: String
    var sizeMB: Int
    var description: String
    var fileURL: String

    static let catalog: [AIModel] = [
        AIModel(
            id: "gemma-2b-it-q4",
            name: "Gemma 2B Instruct (Q4)",
            sizeMB: 1440,
            description: "Modello conversazionale compatto: chat e riassunti offline.",
            fileURL: "https://huggingface.co/google/gemma-2b-it-GGUF/resolve/main/gemma-2b-it.Q4_K_M.gguf"),
        AIModel(
            id: "qwen-05b-instruct-q4",
            name: "Qwen 0.5B Instruct (Q4)",
            sizeMB: 420,
            description: "Piccolo e veloce: idee per didascalie e titoli.",
            fileURL: "https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0_5b-instruct-q4_k_m.gguf"),
        AIModel(
            id: "whisper-tiny-it",
            name: "Whisper Tiny",
            sizeMB: 75,
            description: "Trascrizione audio dei trailer per generare sottotitoli.",
            fileURL: "https://huggingface.co/openai/whisper-tiny/resolve/main/model.bin"),
    ]
}

/// Stato di un download: idle → downloading(progress) → ready.
enum ModelDownloadState: Equatable {
    case idle
    case downloading(progress: Double)
    case ready
}

/// Gestore dei modelli: scarica su file, tiene lo stato in memoria e su disk.
@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published private(set) var states: [String: ModelDownloadState] = [:]
    private var tasks: [String: URLSessionDownloadTask] = [:]

    private var modelsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        // I modelli già scaricati partono da "ready".
        for m in AIModel.catalog {
            if FileManager.default.fileExists(atPath: localFileURL(m.id).path) {
                states[m.id] = .ready
            }
        }
    }

    func state(for model: AIModel) -> ModelDownloadState {
        states[model.id] ?? .idle
    }

    func localFileURL(_ id: String) -> URL {
        modelsDir.appendingPathComponent("\(id).bin")
    }

    func startDownload(_ model: AIModel) {
        guard state(for: model) == .idle, let url = URL(string: model.fileURL) else { return }
        states[model.id] = .downloading(progress: 0)

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, resp, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.tasks[model.id] = nil
                if let tempURL, error == nil {
                    let dest = self.localFileURL(model.id)
                    try? FileManager.default.removeItem(at: dest)
                    try? FileManager.default.moveItem(at: tempURL, to: dest)
                    self.states[model.id] = .ready
                } else {
                    self.states[model.id] = .idle
                }
            }
        }
        tasks[model.id] = task
        task.resume()

        // Progressione via polling dei byte del task (niente KVO: fragile su task)
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self else { return }
                let received = task.countOfBytesReceived
                let expected = task.countOfBytesExpectedToReceive
                await MainActor.run {
                    guard self.tasks[model.id] === task else { return }
                    if expected > 0 {
                        self.states[model.id] = .downloading(progress: Double(received) / Double(expected))
                    }
                }
                if task.state == .completed { break }
            }
        }
    }

    func cancelDownload(_ model: AIModel) {
        tasks[model.id]?.cancel()
        tasks[model.id] = nil
        states[model.id] = .idle
    }

    func removeModel(_ model: AIModel) {
        try? FileManager.default.removeItem(at: localFileURL(model.id))
        states[model.id] = .idle
    }
}

// MARK: - Vista

struct AIModelsView: View {
    @StateObject private var manager = ModelManager.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ScreenHeader(
                    eyebrow: "CineFlash · AI offline",
                    title: "Modelli AI",
                    subtitle: "Scarica i modelli da usare anche senza connessione.")
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(AIModel.catalog) { model in
                        ModelCard(model: model, manager: manager)
                    }
                    Text("I modelli restano solo sul tuo dispositivo: nessun dato viene inviato durante l'uso offline.")
                        .font(Theme.ui(12))
                        .foregroundColor(Theme.textDim)
                        .padding(.top, 8)
                }
                .padding(.horizontal, Theme.pad)
                .padding(.bottom, 32)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

private struct ModelCard: View {
    let model: AIModel
    @ObservedObject var manager: ModelManager

    private var state: ModelDownloadState { manager.state(for: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name)
                        .font(Theme.ui(15, .bold))
                        .foregroundColor(Theme.text)
                    Text("\(model.sizeMB) MB")
                        .font(Theme.ui(11, .semibold))
                        .foregroundColor(Theme.accent)
                }
                Spacer()
                stateBadge
            }

            Text(model.description)
                .font(Theme.ui(13))
                .foregroundColor(Theme.textDim)

            if case .downloading(let p) = state {
                ProgressView(value: p) {
                    Text("Scarico… \(Int(p * 100))%")
                        .font(Theme.ui(11, .semibold))
                        .foregroundColor(Theme.textDim)
                }
                .tint(Theme.accent)
                GhostButton(label: "Annulla") {
                    manager.cancelDownload(model)
                }
            } else if state == .ready {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.ok)
                    Text("Pronto all'uso")
                        .font(Theme.ui(13, .bold))
                        .foregroundColor(Theme.ok)
                }
                GhostButton(label: "🗑 Rimuovi dal dispositivo") {
                    manager.removeModel(model)
                }
            } else {
                PillButton(label: "⬇️ Scarica (\(model.sizeMB) MB)") {
                    manager.startDownload(model)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var stateBadge: some View {
        Group {
            switch state {
            case .idle: Badge(label: "NON SCARICATO", tone: Theme.textDim)
            case .downloading: Badge(label: "IN SCARICO", tone: Theme.warn)
            case .ready: Badge(label: "PRONTO", tone: Theme.ok)
            }
        }
    }
}
