/**
 * Downloader parallelo per modelli GGUF.
 *
 * Il CDN di Hugging Face supporta le richieste Range: invece di una sola
 * connessione lenta, il file viene scaricato in N parti concorrenti
 * (default 6) e poi assemblato in locale. Risultato: 4-6x più veloce.
 *
 * - Ogni parte è un file separato (part-0, part-1, …) in cache: se l'app
 *   viene chiusa, le parti complete NON si riscaricano (resume per parte).
 * - Assemblaggio finale via handle I/O nativi (expo-file-system, new API):
 *   i blocchi passano da JS solo se manca la lettura range del file sorgente,
 *   altrimenti tutto avviene a livello nativo.
 * - A fine assemblaggio le parti vengono eliminate.
 */
import * as FileSystem from "expo-file-system";
import { File, FileHandle, FileMode } from "expo-file-system";

const CONCURRENCY = 6;
/** Dimensione nominale di una parte (25 MiB) per calcolo UI/primo chunk. */
export const PART_SIZE_TARGET = 25 * 1024 * 1024;

interface RangePart {
  index: number;
  start: number;
  /** null = fino alla fine */
  end: number | null;
  /** Dimensione attesa della parte (per il progresso). */
  expected: number;
}

function cacheDir(): string {
  return FileSystem.Paths.cache.uri;
}

function partFile(index: number): File {
  // Prefisso "v2": le parti pre-fix avevano scritture non await-ate
  // (writeBytes e' diventato async in expo-file-system 58) ed erano
  // potenzialmente corrotte: si riparte da un download pulito.
  return new File(FileSystem.Paths.cache, `cineflash-model-part2-${index}`);
}

function legacyPartFile(index: number): File {
  return new File(FileSystem.Paths.cache, `cineflash-model-part-${index}`);
}

async function fileExists(uri: string): Promise<boolean> {
  try {
    return new File(uri).exists;
  } catch {
    return false;
  }
}

async function fileBytes(uri: string): Promise<number> {
  try {
    const f = new File(uri);
    return f.exists ? f.size ?? 0 : 0;
  } catch {
    return 0;
  }
}

/** Ottiene Content-Length e supporto Range del file remoto. */
async function probeRemote(
  url: string
): Promise<{ size: number; ranges: boolean; finalUrl: string }> {
  // Hugging Face risponde con un redirect verso il CDN: fetch lo segue e
  // l'URL finale è quello usato poi per le parti.
  const res = await fetch(url, { method: "GET", headers: { Range: "bytes=0-0" } });
  if (!res.ok) throw new Error(`Impossibile raggiungere il file (HTTP ${res.status})`);
  const cr = res.headers.get("content-range"); // "bytes 0-0/4920758656"
  const totalFromRange = cr?.split("/")[1];
  const cl = res.headers.get("content-length");
  const size = totalFromRange ? parseInt(totalFromRange, 10) : cl ? parseInt(cl, 10) : 0;
  if (!size || isNaN(size)) throw new Error("Dimensione file sconosciuta");
  const acceptRanges = res.headers.get("accept-ranges") ?? "";
  const finalUrl = res.url || url;
  // Consuma il body (1 byte) per liberare la connessione
  try {
    await res.arrayBuffer();
  } catch {}
  return { size, ranges: acceptRanges.toLowerCase() === "bytes" || !!cr, finalUrl };
}

/** Divide il file in parti ~uguali (max CONCURRENCY). */
function splitRanges(size: number): RangePart[] {
  const n = Math.min(CONCURRENCY, Math.max(1, Math.ceil(size / PART_SIZE_TARGET)));
  const partSize = Math.ceil(size / n);
  const parts: RangePart[] = [];
  for (let i = 0; i < n; i++) {
    const start = i * partSize;
    if (start >= size) break;
    const end = Math.min(start + partSize - 1, size - 1);
    parts.push({ index: i, start, end, expected: end - start + 1 });
  }
  return parts;
}

/**
 * Scarica una singola parte con Range. Scrive direttamente su file con
 * streaming (fetch body → Uint8Array chunk → handle nativo).
 */
async function downloadPart(
  url: string,
  part: RangePart,
  existingBytes: number,
  onBytes: (added: number) => void,
  signal: AbortSignal
): Promise<void> {
  const dest = partFile(part.index);
  const rangeHeader =
    existingBytes > 0
      ? `bytes=${part.start + existingBytes}-${part.end ?? ""}`
      : `bytes=${part.start}-${part.end ?? ""}`;

  const res = await fetch(url, {
    headers: { Range: rangeHeader },
    signal,
  });
  if (!res.ok && res.status !== 206) {
    throw new Error(`HTTP ${res.status} sulla parte ${part.index}`);
  }
  if (!res.body) throw new Error("Risposta senza body");

  // Se la parte esiste già parzialmente, appendo; altrimenti riscrivo da zero.
  if (existingBytes > 0) {
    if (!dest.exists) dest.create();
  } else {
    if (dest.exists) dest.delete();
    dest.create();
  }
  const handle: FileHandle = dest.open(
    existingBytes > 0 ? FileMode.Append : FileMode.WriteOnly
  );
  try {
    const reader = res.body.getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value) {
        // writeBytes e' async (expo-file-system 58): l'await garantisce
        // ordine e completamento delle scritture prima della close().
        await handle.writeBytes(value);
        onBytes(value.byteLength);
      }
    }
  } finally {
    handle.close();
  }

  // Verifica dimensione finale della parte
  const got = await fileBytes(dest.uri);
  if (got !== part.expected) {
    throw new Error(
      `Parte ${part.index} incompleta (${got}/${part.expected} byte)`
    );
  }
}

/** Concatena le parti sul file finale, segnalando i byte copiati. */
async function assembleParts(
  parts: RangePart[],
  destFile: File,
  onCopied: (bytes: number) => void
): Promise<void> {
  // Ricrea il file di destinazione vuoto
  try {
    destFile.delete();
  } catch {}
  try {
    destFile.create();
  } catch {}

  const out = destFile.open(FileMode.WriteOnly);
  try {
    for (const part of parts) {
      const src = partFile(part.index);
      // Copia a blocchi con letture native sincrone: affidabile e memory-safe
      // (lo stream API di RN può non emettere mai: blocca l'assemblaggio)
      const inHandle = src.open(FileMode.ReadOnly);
      try {
        const CHUNK = 4 * 1024 * 1024;
        for (;;) {
          let bytes: Uint8Array;
          try {
            bytes = await inHandle.readBytes(CHUNK);
          } catch {
            break; // EOF nativo
          }
          if (!bytes || bytes.byteLength === 0) break;
          // Scrittura await-ata: in expo-file-system 58 writeBytes e' una Promise
          await out.writeBytes(bytes);
          onCopied(bytes.byteLength);
          if (bytes.byteLength < CHUNK) break;
        }
      } finally {
        inHandle.close();
      }
    }
  } finally {
    out.close();
  }
}

/** Elimina le parti scaricate in cache (usato anche quando si rimuove il modello). */
export async function cleanupParts(): Promise<void> {
  for (let i = 0; i < CONCURRENCY * 2; i++) {
    for (const f of [partFile(i), legacyPartFile(i)]) {
      if (await fileExists(f.uri)) {
        try {
          f.delete();
        } catch {}
      }
    }
  }
}

/** Dimensione già presente in cache per il resume (somma delle parti). */
export async function existingPartsBytes(): Promise<number> {
  let total = 0;
  for (let i = 0; i < CONCURRENCY * 2; i++) {
    total += await fileBytes(partFile(i).uri);
  }
  return total;
}

export type ParallelStage = "probe" | "downloading" | "assembling";

export interface ParallelDownloadHandle {
  promise: Promise<void>;
  cancel: () => void;
}

/**
 * Scarica `url` su `destPath` (file://) usando CONCURRENCY connessioni.
 * onProgress riceve (scaricati, totali) durante il download;
 * onStage segnala le fasi (probe/downloading/assembling) con progresso.
 */
export function parallelDownload(
  url: string,
  destPath: string,
  onProgress: (done: number, total: number) => void,
  onStage?: (stage: ParallelStage, done: number, total: number) => void
): ParallelDownloadHandle {
  const controller = new AbortController();
  const promise = (async () => {
    onStage?.("probe", 0, 1);
    const { size, ranges, finalUrl } = await probeRemote(url);
    if (!ranges) {
      // CDN senza Range: fallback a parte unica (comunque streaming su file)
      const parts = [{ index: 0, start: 0, end: null, expected: size }];
      let done0 = 0;
      await downloadPart(finalUrl, parts[0], 0, (b) => {
        done0 += b;
        onProgress(done0, size);
      }, controller.signal);
      onStage?.("assembling", 0, size);
      let doneA = 0;
      await assembleParts(parts, new File(destPath), (b) => {
        doneA += b;
        onStage?.("assembling", doneA, size);
      });
      await cleanupParts();
      return;
    }

    const parts = splitRanges(size);
    let done = await existingPartsBytes();
    const total = size;
    onStage?.("downloading", done, total);

    // Limita la concorrenza effettiva alle parti rimanenti
    const queue = [...parts];
    const errors: Error[] = [];
    const active = new Set<Promise<void>>();

    const worker = async () => {
      for (;;) {
        if (controller.signal.aborted) return;
        const part = queue.shift();
        if (!part) return;
        // Salta le parti già complete
        const dest = partFile(part.index);
        const have = await fileBytes(dest.uri);
        if (have === part.expected) {
          // già completa
          continue;
        }
        if (have > part.expected) {
          try {
            dest.delete();
          } catch {}
        }
        const task = downloadPart(
          finalUrl,
          part,
          Math.min(have, part.expected),
          (b) => {
            done += b;
            onProgress(done, total);
          },
          controller.signal
        ).catch((e) => {
          if (!controller.signal.aborted) errors.push(e);
        });
        active.add(task);
        await task;
        active.delete(task);
        if (errors.length > 0) return;
      }
    };

    await Promise.all(
      Array.from({ length: Math.min(CONCURRENCY, parts.length) }, worker)
    );

    if (controller.signal.aborted) throw new Error("cancelled");
    if (errors.length > 0) {
      throw errors[0];
    }

    // Verifica che tutte le parti siano complete
    for (const part of parts) {
      const have = await fileBytes(partFile(part.index).uri);
      if (have !== part.expected) {
        throw new Error(`Parte ${part.index} mancante dopo il download`);
      }
    }

    onProgress(total, total);
    onStage?.("assembling", 0, total);
    let assembled = 0;
    let lastPct = -1;
    await assembleParts(parts, new File(destPath), (bytes) => {
      assembled += bytes;
      const pct = Math.floor((assembled / total) * 100);
      if (pct !== lastPct) {
        lastPct = pct;
        onStage?.("assembling", assembled, total);
      }
    });

    // Verifica finale: il file assemblato deve essere grande come l'originale
    const finalSize = await fileBytes(destPath);
    if (finalSize !== size) {
      throw new Error(`File finale incompleto (${finalSize}/${size})`);
    }

    await cleanupParts();
  })();

  return { promise, cancel: () => controller.abort() };
}
