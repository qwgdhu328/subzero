import * as Notifications from "expo-notifications";
import * as BackgroundFetch from "expo-background-fetch";
import * as TaskManager from "expo-task-manager";
import { NewsItem } from "../models/types";
import { isPreSale } from "./alerts";
import {
  activeSources,
  loadSettings,
  loadNewsCache,
  saveNewsCache,
} from "../storage/store";
import { fetchAllNews } from "./news";

export const BACKGROUND_TASK = "cineflash-background-news";
/** Età massima di un articolo per cui notifichiamo (evita spam al primo avvio). */
const MAX_NEW_AGE_MS = 10 * 60 * 1000;
const MAX_ITEMS = 120;

/* ---------- Handler notifiche (mostra mentre l'app è aperta) ---------- */

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
});

/* ---------- Permesso ---------- */

export async function ensureNotificationPermission(): Promise<boolean> {
  const cur = await Notifications.getPermissionsAsync();
  if (cur.granted) return true;
  if (!cur.canAskAgain) return false;
  const req = await Notifications.requestPermissionsAsync();
  return req.granted;
}

/* ---------- Rilevamento nuovi articoli ---------- */

export interface RefreshResult {
  fresh: NewsItem[];
  /** articoli completamente nuovi (per pill/badge) */
  newCount: number;
  /** nuovi articoli su prevendite */
  newPreSaleCount: number;
  failed: string[];
}

/**
 * Scarica i feed, confronta con la cache e salva.
 * Non notifica: la notifica è responsabilità del chiamante.
 */
export async function refreshNews(): Promise<RefreshResult> {
  const settings = await loadSettings();
  const sources = activeSources(settings);
  const { items: fetched, failed } = await fetchAllNews(sources);

  const cached = await loadNewsCache();
  const oldIds = new Set((cached?.items ?? []).map((x) => x.id));
  const now = Date.now();

  const fresh = fetched.filter(
    (x) =>
      !oldIds.has(x.id) &&
      x.publishedAt != null &&
      now - Date.parse(x.publishedAt) <= MAX_NEW_AGE_MS
  );

  const merged = mergeItems(fetched, cached?.items ?? []);
  if (merged.length > 0) {
    await saveNewsCache({ fetchedAt: new Date().toISOString(), items: merged });
  }

  return {
    fresh,
    newCount: fresh.length,
    newPreSaleCount: fresh.filter(isPreSale).length,
    failed,
  };
}

/** Unione dedup: prima i più recenti, limite MAX_ITEMS. */
function mergeItems(a: NewsItem[], b: NewsItem[]): NewsItem[] {
  const seen = new Set<string>();
  const out: NewsItem[] = [];
  for (const x of [...a, ...b]) {
    if (seen.has(x.id)) continue;
    seen.add(x.id);
    out.push(x);
  }
  out.sort((x, y) => {
    const tx = x.publishedAt ? Date.parse(x.publishedAt) : 0;
    const ty = y.publishedAt ? Date.parse(y.publishedAt) : 0;
    return ty - tx;
  });
  return out.slice(0, MAX_ITEMS);
}

/* ---------- Notifica locale ---------- */

export async function notifyNewItems(res: RefreshResult): Promise<void> {
  if (res.newCount === 0) return;
  const settings = await loadSettings();
  if (settings.notifyEnabled === false) return;
  const granted = await ensureNotificationPermission();
  if (!granted) return;

  const preSale = res.fresh.filter(isPreSale);
  // 1 notifica per le prevendite (le più urgenti) + 1 per il resto
  if (preSale.length > 0) {
    await Notifications.scheduleNotificationAsync({
      content: {
        title: "🎟️ Prevendite aperte!",
        body:
          preSale.length === 1
            ? preSale[0].title
            : `${preSale.length} nuovi titoli con biglietti in vendita: ${preSale
                .slice(0, 2)
                .map((x) => x.title)
                .join(", ")}…`,
        sound: true,
      },
      trigger: null, // subito
    });
  }
  const others = res.fresh.filter((x) => !isPreSale(x));
  if (others.length > 0) {
    await Notifications.scheduleNotificationAsync({
      content: {
        title: "🎬 Nuove notizie cinema",
        body:
          others.length === 1
            ? others[0].title
            : `${others.length} nuove notizie: ${others
                .slice(0, 2)
                .map((x) => x.title)
                .join(", ")}…`,
        sound: false,
      },
      trigger: null,
    });
  }
}

/* ---------- Background fetch (aggiorna anche con l'app chiusa) ---------- */

TaskManager.defineTask(BACKGROUND_TASK, async () => {
  try {
    const res = await refreshNews();
    await notifyNewItems(res);
    return res.newCount > 0
      ? BackgroundFetch.BackgroundFetchResult.NewData
      : BackgroundFetch.BackgroundFetchResult.NoData;
  } catch {
    return BackgroundFetch.BackgroundFetchResult.Failed;
  }
});

export async function registerBackgroundFetch(): Promise<void> {
  try {
    const status = await BackgroundFetch.getStatusAsync();
    if (
      status === BackgroundFetch.BackgroundFetchStatus.Denied ||
      status === BackgroundFetch.BackgroundFetchStatus.Restricted
    )
      return;
    await BackgroundFetch.registerTaskAsync(BACKGROUND_TASK, {
      minimumInterval: 15, // minuti (iOS decide poi in base all'uso)
      stopOnTerminate: false,
      startOnBoot: true,
    });
  } catch {
    // task già registrato o non disponibile (es. Expo Go su Android)
  }
}
