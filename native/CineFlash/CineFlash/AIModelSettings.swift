import SwiftUI
import UIKit

/// Impostazioni AI: scelta del modello (tra quelli gratuiti OpenRouter),
/// con test di connessione e stato salvato nelle impostazioni.

// MARK: - Impostazioni extra per l'AI

extension AIModelPrefs {
    static func load() -> AIModelPrefs {
        let d = UserDefaults.standard
        return AIModelPrefs(
            preferredModel: d.string(forKey: "cineflash/ai-model") ?? "auto",
            lastTestOk: d.object(forKey: "cineflash/ai-test-ok") as? Bool,
            lastTestAt: d.object(forKey: "cineflash/ai-test-at") as? Date,
            lastTestLatencyMs: d.object(forKey: "cineflash/ai-test-latency") as? Int
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(preferredModel, forKey: "cineflash/ai-model")
        d.set(lastTestOk, forKey: "cineflash/ai-test-ok")
        d.set(lastTestAt, forKey: "cineflash/ai-test-at")
        d.set(lastTestLatencyMs, forKey: "cineflash/ai-test-latency")
    }
}

struct AIModelPrefs {
    var preferredModel: String // "auto" oppure id modello
    var lastTestOk: Bool?
    var lastTestAt: Date?
    var lastTestLatencyMs: Int?
}

// MARK: - Test di connessione

enum AIModelTester {
    /// Risultato del test di un modello: ok + latenza, oppure errore.
    static func test(_ model: String) async -> (ok: Bool, latencyMs: Int, error: String?) {
        let start = Date()
        do {
            let reply = try await AIService.askCloudWithModel(model, question: "Rispondi solo con: OK")
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let good = !reply.trimmingCharacters(in: .whitespaces).isEmpty
            return (good, ms, good ? nil : "risposta vuota")
        } catch {
            return (false, Int(Date().timeIntervalSince(start) * 1000), error.localizedDescription)
        }
    }
}

// MARK: - Vista

struct AIModelSettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var prefs = AIModelPrefs.load()
    @State private var testing: String? = nil
    @State private var testError: String? = nil

    private let models: [(id: String, name: String)] = [
        ("auto", "🤖 Automatico (prova tutti in sequenza)"),
        ("z-ai/glm-4.5-air:free", "GLM 4.5 Air — veloce, ragiona"),
        ("z-ai/glm-5.2:free", "GLM 5.2 — equilibrato"),
        ("meta-llama/llama-3.3-70b-instruct:free", "Llama 3.3 70B — più profondo"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: { dismiss() }) {
                        Text("‹").font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                            .frame(width: 38, height: 38)
                            .background(Theme.surfaceAlt.cornerRadius(19))
                            .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                Text("Modello AI").font(Theme.serif(28)).foregroundColor(Theme.text)
                Text("Scegli quale modello gratuito OpenRouter usare per la chat e la redazione. \"Automatico\" prova tutti in sequenza fino a quando uno risponde.")
                    .font(Theme.ui(13)).foregroundColor(Theme.textDim)

                // MARK: Selezione modello
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(models, id: \.id) { m in
                        Button {
                            prefs.preferredModel = m.id
                            prefs.save()
                            NotificationCenter.default.post(name: .aiModelChanged, object: nil)
                        } label: {
                            HStack {
                                Text(m.name)
                                    .font(Theme.ui(14, prefs.preferredModel == m.id ? .bold : .regular))
                                    .foregroundColor(Theme.text)
                                Spacer()
                                if prefs.preferredModel == m.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if m.id != models.last?.id {
                            Divider().overlay(Theme.border)
                        }
                    }
                }
                .background(Theme.surface.cornerRadius(Theme.radiusMd))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).stroke(Theme.border, lineWidth: 0.5))

                // MARK: Test di connessione
                VStack(alignment: .leading, spacing: 10) {
                    Text("TEST DI CONNESSIONE")
                        .font(.system(size: 12, weight: .bold)).kerning(1.2)
                        .foregroundColor(Theme.textDim)

                    let target = prefs.preferredModel == "auto" ? "z-ai/glm-4.5-air:free" : prefs.preferredModel

                    if let testing {
                        HStack(spacing: 8) {
                            ProgressView().tint(Theme.accent).scaleEffect(0.8)
                            Text("Provo \(modelName(testing))…")
                                .font(Theme.ui(13)).foregroundColor(Theme.textDim)
                        }
                    } else if let ok = prefs.lastTestOk {
                        HStack(spacing: 8) {
                            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(ok ? Theme.ok : Theme.danger)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ok ? "Connessione OK" : "Connessione fallita")
                                    .font(Theme.ui(14, .bold))
                                    .foregroundColor(ok ? Theme.ok : Theme.danger)
                                if let ms = prefs.lastTestLatencyMs, let at = prefs.lastTestAt {
                                    Text("\(ms) ms · \(at.formatted(date: .abbreviated, time: .shortened))")
                                        .font(Theme.ui(11)).foregroundColor(Theme.textDim)
                                }
                            }
                        }
                    }

                    if let e = testError {
                        Text(e).font(Theme.ui(12)).foregroundColor(Theme.warn)
                    }

                    PillButton(label: testing == nil ? "⚡ Prova la connessione" : "Test in corso…") {
                        runTest(model: target)
                    }
                    .disabled(testing != nil)

                    Text("Il test invia un messaggio minimo al modello e misura il tempo di risposta.")
                        .font(Theme.ui(11)).foregroundColor(Theme.textDim)
                }
                .cardSurface()
            }
            .padding(Theme.pad)
            .padding(.bottom, 40)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    private func modelName(_ id: String) -> String {
        models.first(where: { $0.id == id })?.name ?? id
    }

    private func runTest(model: String) {
        testing = model
        testError = nil
        Task {
            let result = await AIModelTester.test(model)
            await MainActor.run {
                prefs.lastTestOk = result.ok
                prefs.lastTestLatencyMs = result.latencyMs
                prefs.lastTestAt = Date()
                prefs.save()
                if !result.ok, let err = result.error {
                    testError = err
                }
                testing = nil
            }
        }
    }
}

extension Notification.Name {
    static let aiModelChanged = Notification.Name("cineflash.aiModelChanged")
}

// MARK: - Integrazione in Impostazioni (card dedicata)

struct AIModelCard: View {
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MODELLO AI")
                .font(.system(size: 12, weight: .bold)).kerning(1.2)
                .foregroundColor(Theme.textDim)
            Text("Scegli il modello gratuito e prova la connessione.")
                .font(Theme.ui(13)).foregroundColor(Theme.textDim)
            GhostButton(label: "⚙ Configura il modello") { showPicker = true }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .sheet(isPresented: $showPicker) { AIModelSettingsView() }
    }
}
