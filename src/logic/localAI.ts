/**
 * AI locale (on-device) per CineFlash.
 *
 * Usa llama.rn (llama.cpp per React Native) con accelerazione Metal su iPhone:
 * il modello GGUF classe 7B/8B viene scaricato una volta da Hugging Face e
 * salvato nella cartella documenti dell'app. Nessun dato lascia il telefono.
 */

import { Platform } from "react-native";
import type { LlamaContext } from "llama.rn";
import * as LegacyFS from "expo-file-system/legacy";
import Constants from "expo-constants";
import {
  parallelDownload,
  existingPartsBytes,
  type ParallelStage,
} from "./parallelDownload";

/* ---------- Catalogo modelli (GGUF quantizzati Q4_K_M, classe 7-8B) ---------- */

export interface AIModelDef {
  key: string;
  name: string;
  sizeGB: number;
  url: string;
  /** Descrizione breve mostrata nella scelta. */
  note: string;
}

export const AI_MODELS: AIModelDef[] = [
  {
    key: "llama31-8b",
    name: "Llama 3.1 8B",
    sizeGB: 4.9,
    url: "https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
    note: "Consigliato · il migliore per spiegare notizie e film",
  },
  {
    key: "qwen25-7b",
    name: "Qwen 2.5 7B",
    sizeGB: 4.7,
    url: "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf",
    note: "Ottimo in italiano, risposte ordinate",
  },
  {
    key: "llama32-3b",
    name: "Llama 3.2 3B (leggero)",
    sizeGB: 2.0,
    url: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
    note: "Per iPhone con poca memoria, più veloce e più semplice",
  },
];

export const DEFAULT_AI_MODEL_KEY = "llama31-8b";

/* ---------- Impostazioni AI (campi aggiunti a Settings in models/types) ---------- */

export function getAIModel(key: string | null | undefined): AIModelDef {
  return AI_MODELS.find((m) => m.key === key) ?? AI_MODELS[0];
}

/* ---------- Percorsi e stato del file modello ---------- */

const MODEL_DIR = `${LegacyFS.documentDirectory}ai-models/`;
const modelPath = (def: AIModelDef) => `${MODEL_DIR}${def.key}.gguf`;

/**
 * Percorso file:// del modello scaricato, o null se assente.
 * Se esiste il file MA restano parti in cache (crash durante l'assemblaggio),
 * il file è incompleto: viene eliminato e si riscarica al prossimo giro.
 */
export async function getDownloadedModelPath(
  def: AIModelDef
): Promise<string | null> {
  try {
    const info = await LegacyFS.getInfoAsync(modelPath(def));
    if (info.exists && !info.isDirectory && (info.size ?? 0) > 1_000_000) {
      const leftover = await existingPartsBytes();
      if (leftover > 0) {
        // Assemblaggio interrotto: file parziale, va rifatto
        await LegacyFS.deleteAsync(modelPath(def), { idempotent: true });
        return null;
      }
      return modelPath(def);
    }
  } catch {}
  return null;
}

/* ---------- Download con progresso ---------- */

export interface DownloadState {
  downloading: boolean;
  /** 0-1 */
  progress: number;
}

let activeDownload: { def: AIModelDef; cancel: () => void } | null = null;

export function isDownloading(): boolean {
  return activeDownload != null;
}

/** Byte già in cache (parti scaricate) per il resume. */
export async function downloadedBytes(): Promise<number> {
  return existingPartsBytes();
}

/**
 * Scarica il modello GGUF (resumable, ~5 GB). onProgress riceve 0-1.
 * Ritorna il percorso file:// del modello scaricato.
 */
export async function downloadModel(
  def: AIModelDef,
  onProgress: (progress: number) => void
): Promise<string> {
  if (activeDownload) throw new Error("Download già in corso");
  const existing = await getDownloadedModelPath(def);
  if (existing) return existing;

  try {
    await LegacyFS.makeDirectoryAsync(MODEL_DIR, { intermediates: true });
  } catch {}

  // Download parallelo: 6 connessioni simultanee al CDN (4-6x più veloce),
  // resume per parte e assemblaggio finale via I/O nativo.
  const handle = parallelDownload(
    def.url,
    modelPath(def),
    (done, total) => {
      onProgress(total > 0 ? done / total : 0);
    },
    (stage: ParallelStage, done: number, total: number) => {
      if (stage === "assembling") {
        // Sposta lo stato in "assemblaggio": la UI esce dal 100% di download
        updateAI({
          phase: "assembling",
          progress: total > 0 ? done / total : 0,
        });
      }
    }
  );
  activeDownload = { def, cancel: handle.cancel };

  try {
    await handle.promise;
    const path = await getDownloadedModelPath(def);
    if (!path) throw new Error("File modello non trovato dopo il download");
    return path;
  } catch (e) {
    // Mantieni le parti scaricate per riprendere al prossimo tentativo;
    // solo un annullamento esplicito le pulisce.
    throw e instanceof Error ? e : new Error("Download non riuscito");
  } finally {
    activeDownload = null;
  }
}

export function cancelDownload(): void {
  activeDownload?.cancel();
}

/** Elimina il modello scaricato per liberare spazio (incl. le parti in cache). */
export async function deleteModelFile(def: AIModelDef): Promise<void> {
  if (isDownloading()) cancelDownload();
  try {
    await LegacyFS.deleteAsync(modelPath(def), { idempotent: true });
  } catch {}
  // Pulisce anche eventuali parti parallele lasciate in cache
  try {
    const { cleanupParts } = await import("./parallelDownload");
    await cleanupParts();
  } catch {}
}

/* ---------- Motore: caricamento del contesto e chat ---------- */

const STOP_WORDS = [
  "<|end|>",
  "<|eot_id|>",
  "<|end_of_text|>",
  "<|im_end|>",
  "<|endoftext|>",
  "<|end_of_turn|>",
  "<|EOT|>",
];

const SYSTEM_PROMPT = `Sei l'assistente AI di CineFlash, app italiana di cinema. Rispondi SEMPRE in italiano, in modo chiaro e semplice, come se lo spiegassi a un amico che non è esperto di cinema. Usa frasi brevi. Quando parli di un film, spiega di cosa parla senza spoiler importanti. Se una domanda non riguarda il cinema o la notizia data, rispondi comunque in modo utile e breve.`;

interface LoadedEngine {
  def: AIModelDef;
  ctx: LlamaContext;
}

/**
 * llama.rn è un modulo nativo-only: il suo import esegue codice che accede ai
 * moduli nativi e va in crash sul browser. Viene quindi caricato solo quando
 * serve, e mai su web.
 */
async function loadLlamaLib(): Promise<typeof import("llama.rn")> {
  if (Platform.OS === "web") {
    throw new Error(
      "L'AI locale non è disponibile su web: funziona nell'app su iPhone e Android."
    );
  }
  return import("llama.rn");
}

let engine: LoadedEngine | null = null;

export function isEngineReady(): boolean {
  return engine != null;
}

/** Carica il modello in memoria (può richiedere qualche secondo). */
export async function loadEngine(
  def: AIModelDef,
  onProgress?: (p: number) => void
): Promise<LoadedEngine> {
  if (engine && engine.def.key === def.key) return engine;
  await unloadEngine();
  const path =
    (await getDownloadedModelPath(def)) ??
    (await downloadModel(def, (p) => onProgress?.(p * 0.1)));
  onProgress?.(0.15);
  const { initLlama } = await loadLlamaLib();
  const ctx = await initLlama({
    model: path,
    n_ctx: 2048,
    n_gpu_layers: 99, // Metal su iPhone
    n_batch: 512,
    use_progress_callback: true,
  });
  onProgress?.(1);
  engine = { def, ctx };
  return engine;
}

/** Richiesta di chat in corso (per uno streaming coerente). */
let pendingChatId = 0;

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

/**
 * Chat con contesto opzionale (titolo, testo della notizia o trama del film).
 * onDelta viene chiamato per ogni pezzo di risposta generato (streaming).
 * Ritorna il testo completo.
 */
export async function chat(
  userQuestion: string,
  context: { title?: string; text?: string; source?: string } | null,
  history: ChatMessage[],
  onDelta: (partial: string) => void
): Promise<string> {
  if (!engine) throw new Error("AI non pronta");
  const requestId = ++pendingChatId;

  const ctxInfo = context?.text
    ? `\n\n---\nCONTESTO${context.source ? ` (${context.source})` : ""}${
        context.title ? ` — ${context.title}` : ""
      }:\n${context.text}\n---\n`
    : "";

  const messages = [
    { role: "system" as const, content: SYSTEM_PROMPT + ctxInfo },
    ...history.slice(-6).map((m) => ({ role: m.role, content: m.content })),
    { role: "user" as const, content: userQuestion },
  ];

  let acc = "";
  const result = await engine.ctx.completion(
    {
      messages,
      n_predict: 500,
      temperature: 0.6,
      top_p: 0.9,
      stop: STOP_WORDS,
      jinja: true,
      enable_thinking: false,
    },
    (data) => {
      if (requestId !== pendingChatId) return; // risposta superata/annullata
      if (data.token) {
        acc += data.token;
        onDelta(acc);
      }
    }
  );

  if (requestId !== pendingChatId) return acc;
  const finalText = (result.text ?? "").trim() || acc.trim();
  onDelta(finalText);
  return finalText;
}

/** Interrompe la generazione in corso. */
export async function stopChat(): Promise<void> {
  pendingChatId++;
  try {
    await engine?.ctx.stopCompletion();
  } catch {}
}

/** Scarica il modello dalla memoria (l'utente può chiederlo da Impostazioni). */
export async function unloadEngine(): Promise<void> {
  pendingChatId++;
  if (engine) {
    try {
      await engine.ctx.release();
    } catch {}
    engine = null;
  }
}

/** Rilascia tutto (chiamato all'avvio per sicurezza). */
export async function resetAI(): Promise<void> {
  await unloadEngine();
  try {
    const { releaseAllLlama } = await loadLlamaLib();
    await releaseAllLlama();
  } catch {}
}

/* ---------- Avvio automatico (bootstrap) ----------
 *
 * All'apertura dell'app l'app scarica il modello da sola e lo carica:
 * la pagina AI resta "in manutenzione" finché non è pronta, poi si
 * sblocca automaticamente. Alle aperture successive il modello è già
 * sul telefono: nessun download, solo caricamento.
 */

export type AIPhase =
  | "idle"
  | "downloading"
  | "assembling"
  | "loading"
  | "ready"
  | "error";

export interface AIState {
  phase: AIPhase;
  /** 0-1, valido durante "downloading". */
  progress: number;
  /** Modello coinvolto nella fase corrente. */
  modelKey: string | null;
  error: string | null;
}

let aiState: AIState = { phase: "idle", progress: 0, modelKey: null, error: null };
const aiListeners = new Set<() => void>();

function updateAI(patch: Partial<AIState>): void {
  aiState = { ...aiState, ...patch };
  aiListeners.forEach((l) => l());
}

/** Snapshot corrente (stabile tra i render, per useSyncExternalStore). */
export function getAIState(): AIState {
  return aiState;
}

/** Sottoscrizione ai cambi di stato dell'AI. */
export function subscribeAI(listener: () => void): () => void {
  aiListeners.add(listener);
  return () => aiListeners.delete(listener);
}

let bootstrapPromise: Promise<void> | null = null;

/** Modelli per cui l'auto-riparazione (riscarico) e' gia' stata tentata in questa sessione. */
const healAttempted = new Set<string>();

/**
 * In Expo Go i moduli nativi di terze parti (llama.rn) non esistono:
 * l'AI locale richiede una development build installata sul telefono.
 */
export function isExpoGo(): boolean {
  return Constants.appOwnership === "expo";
}

/**
 * Prepara l'AI in automatico: scarica il modello se manca (una sola volta),
 * poi lo carica in memoria. Idempotente: chiamate multiple convergono.
 */
export async function startAIBootstrap(modelKey?: string): Promise<void> {
  if (Platform.OS === "web") {
    updateAI({
      phase: "error",
      error:
        "L'AI locale non è disponibile su web: funziona solo nell'app installata su iPhone o Android.",
    });
    return;
  }
  if (isExpoGo()) {
    updateAI({
      phase: "error",
      error:
        "L'AI locale richiede l'app installata sul telefono (development build): in Expo Go il modulo AI nativo non è disponibile.",
    });
    return;
  }
  const def = getAIModel(modelKey ?? aiState.modelKey ?? undefined);
  if (engine) {
    // Motore già caricato: pronto se è lo stesso modello, altrimenti ricarica
    if (engine.def.key === def.key) {
      updateAI({ phase: "ready", progress: 1, error: null });
      return;
    }
    await unloadEngine();
  }
  if (bootstrapPromise) return bootstrapPromise;
  bootstrapPromise = (async () => {
    const reportProgress = (p: number) => {
      const clamped = Math.min(1, Math.max(0, p));
      if (Math.abs(clamped - aiState.progress) > 0.002 || clamped >= 1) {
        updateAI({ progress: clamped });
      }
    };
    try {
      let path = await getDownloadedModelPath(def);
      if (!path) {
        updateAI({
          phase: "downloading",
          progress: 0,
          modelKey: def.key,
          error: null,
        });
        path = await downloadModel(def, reportProgress);
      }
      updateAI({ phase: "loading", progress: 1, modelKey: def.key, error: null });
      try {
        await loadEngine(def);
      } catch (loadErr) {
        // Il file potrebbe essere corrotto (es. scaricato con la versione
        // precedente del downloader, con scritture non await-ate): riscarico
        // una sola volta per sessione, poi riporto l'errore reale.
        if (healAttempted.has(def.key)) throw loadErr;
        healAttempted.add(def.key);
        await deleteModelFile(def);
        updateAI({ phase: "downloading", progress: 0, modelKey: def.key, error: null });
        await downloadModel(def, reportProgress);
        updateAI({ phase: "loading", progress: 1, modelKey: def.key, error: null });
        await loadEngine(def);
      }
      updateAI({ phase: "ready", progress: 1, error: null });
    } catch (e) {
      updateAI({
        phase: "error",
        error: e instanceof Error ? e.message : "Preparazione AI non riuscita",
      });
    } finally {
      bootstrapPromise = null;
    }
  })();
  return bootstrapPromise;
}

/** Riprova dopo un errore (dalla pagina AI o dalle Impostazioni). */
export function retryAIBootstrap(): void {
  if (bootstrapPromise) return;
  updateAI({ phase: "idle", error: null });
  startAIBootstrap().catch(() => {});
}

/* ---------- Aiutante: prompt preimpostati per notizie e film ---------- */

export function quickPromptsNews(title: string): { label: string; q: string }[] {
  return [
    {
      label: "Spiegami questa notizia",
      q: `Spiegami in parole semplici questa notizia di cinema: "${title}". Cosa significa e perché è importante?`,
    },
    {
      label: "Di cosa parla il film?",
      q: `In questa notizia viene menzionato un film. Dimmi di cosa parla e perché è rilevante per la notizia: "${title}".`,
    },
    {
      label: "Perché è importante?",
      q: `Perché questa notizia è importante per il mondo del cinema: "${title}"? Spiegami il contesto.`,
    },
  ];
}

export function quickPromptsMovie(title: string): { label: string; q: string }[] {
  return [
    {
      label: "Spiegami la trama",
      q: `Spiegami in parole semplici la trama del film "${title}" senza spoiler importanti.`,
    },
    {
      label: "Che genere è?",
      q: `Che tipo di film è "${title}"? A cosa o a quali film somiglia?`,
    },
    {
      label: "Me lo consigli?",
      q: `Considerando trama e genere, a chi consiglieresti il film "${title}"? Spiega perché.`,
    },
  ];
}
