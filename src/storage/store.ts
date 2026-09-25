import AsyncStorage from "@react-native-async-storage/async-storage";
import { useEffect, useState } from "react";
import { NewsSource, Settings } from "../models/types";

const KEY_SETTINGS = "cineflash/settings/v1";
const KEY_NEWS_CACHE = "cineflash/news-cache/v1";
const KEY_MOVIES_CACHE = "cineflash/movies-cache/v1";

/**
 * Feed RSS cinema italiani predefiniti.
 * URL verificati: i siti senza feed pubblici o con anti-bot (MyMovies,
 * FilmTv, Il Post, ecc.) sono stati rimossi.
 */
export const DEFAULT_SOURCES: NewsSource[] = [
  {
    key: "ansa",
    name: "ANSA Cinema",
    url: "https://www.ansa.it/sito/notizie/cultura/cinema/cinema_rss.xml",
    enabled: true,
  },
  {
    key: "badtaste",
    name: "BadTaste",
    url: "https://www.badtaste.it/feed",
    enabled: true,
  },
  {
    key: "cineblog",
    name: "CineBlog",
    url: "https://www.cineblog.it/feed",
    enabled: true,
  },
  {
    key: "ciak",
    name: "Ciak Magazine",
    url: "https://www.ciakmagazine.it/feed/",
    enabled: true,
  },
  {
    key: "comingsoon",
    name: "ComingSoon.it",
    url: "https://www.comingsoon.it/feedrss/",
    enabled: true,
  },
];

/**
 * Fonti consigliate (feed RSS cinema italiani verificati attivi).
 * Vengono aggiunte una sola volta alle fonti custom al primo avvio: l'utente
 * può rimuoverle come qualsiasi fonte custom e non vengono ricreate.
 */
export const SUGGESTED_SOURCES: NewsSource[] = [
  {
    key: "suggested_everyeye",
    name: "Everyeye Cinema",
    url: "https://cinema.everyeye.it/feed/",
    enabled: true,
  },
  {
    key: "suggested_bestmovie",
    name: "Best Movie",
    url: "https://www.bestmovie.it/feed/",
    enabled: true,
  },
  {
    key: "suggested_screenweek",
    name: "ScreenWeek",
    url: "https://www.screenweek.it/feed/",
    enabled: true,
  },
  {
    key: "suggested_cinefiliaritrovata",
    name: "Cinefilia Ritrovata",
    url: "https://www.cinefiliaritrovata.it/feed/",
    enabled: true,
  },
  {
    key: "suggested_filmidee",
    name: "FilmIdee",
    url: "https://www.filmidee.it/feed/",
    enabled: true,
  },
  {
    key: "suggested_spaziofilm",
    name: "SpazioFilm",
    url: "https://www.spaziofilm.it/feed/",
    enabled: true,
  },
  {
    key: "suggested_nocturno",
    name: "Nocturno",
    url: "https://www.nocturno.it/feed/",
    enabled: true,
  },
];

/**
 * Chiave TMDB inclusa nell'app: la tab Film funziona out-of-the-box con i
 * cataloghi TMDB completi, senza configurazione.
 */
export const BUILT_IN_TMDB_API_KEY = "ea95fe5f63cc25fb347f0d7c813bb40a";

export const DEFAULT_SETTINGS: Settings = {
  tmdbApiKey: BUILT_IN_TMDB_API_KEY,
  customSources: [],
  disabledSources: [],
  aiModelKey: "llama31-8b",
  aiDisabled: false,
};

export function activeSources(settings: Settings): NewsSource[] {
  const defaults = DEFAULT_SOURCES.map((s) =>
    settings.disabledSources.includes(s.key) ? { ...s, enabled: false } : s
  );
  return [...defaults, ...settings.customSources].filter((s) => s.enabled);
}

export async function loadSettings(): Promise<Settings> {
  try {
    const raw = await AsyncStorage.getItem(KEY_SETTINGS);
    const parsed = raw ? (JSON.parse(raw) as Partial<Settings>) : {};
    let merged: Settings = {
      ...DEFAULT_SETTINGS,
      ...parsed,
      tmdbApiKey: parsed.tmdbApiKey?.trim() ? parsed.tmdbApiKey : BUILT_IN_TMDB_API_KEY,
    };
    // Prima volta: semina le fonti consigliate tra le custom (una sola volta,
    // così se l'utente le rimuove non tornano al prossimo avvio).
    if (!merged.suggestedSeeded) {
      const existing = new Set(merged.customSources.map((x) => x.key));
      const toAdd = SUGGESTED_SOURCES.filter((x) => !existing.has(x.key));
      merged = {
        ...merged,
        customSources: [...merged.customSources, ...toAdd],
        suggestedSeeded: true,
      };
    }
    return merged;
  } catch {}
  return DEFAULT_SETTINGS;
}

export async function saveSettings(s: Settings): Promise<void> {
  await AsyncStorage.setItem(KEY_SETTINGS, JSON.stringify(s));
}

export interface NewsCache {
  /** ISO date del fetch. */
  fetchedAt: string;
  items: import("../models/types").NewsItem[];
}

export async function loadNewsCache(): Promise<NewsCache | null> {
  try {
    const raw = await AsyncStorage.getItem(KEY_NEWS_CACHE);
    if (raw) return JSON.parse(raw) as NewsCache;
  } catch {}
  return null;
}

export async function saveNewsCache(cache: NewsCache): Promise<void> {
  await AsyncStorage.setItem(KEY_NEWS_CACHE, JSON.stringify(cache));
}

export interface MoviesCache {
  fetchedAt: string;
  provider: "tmdb" | "itunes";
  nowPlaying: import("../models/types").Movie[];
  upcoming: import("../models/types").Movie[];
  popular: import("../models/types").Movie[];
}

export async function loadMoviesCache(): Promise<MoviesCache | null> {
  try {
    const raw = await AsyncStorage.getItem(KEY_MOVIES_CACHE);
    if (raw) return JSON.parse(raw) as MoviesCache;
  } catch {}
  return null;
}

export async function saveMoviesCache(cache: MoviesCache): Promise<void> {
  await AsyncStorage.setItem(KEY_MOVIES_CACHE, JSON.stringify(cache));
}

/** Hook: stato centralizzato con persistenza automatica. */
export function useStore() {
  const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setSettings(await loadSettings());
      setLoading(false);
    })();
  }, []);

  useEffect(() => {
    if (!loading) saveSettings(settings).catch(() => {});
  }, [settings, loading]);

  const update = (patch: Partial<Settings>) =>
    setSettings((prev) => ({ ...prev, ...patch }));

  return { settings, setSettings, update, loading };
}
