import { useCallback, useEffect, useState } from "react";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { NewsItem } from "../models/types";
import * as Haptics from "expo-haptics";

const KEY_SAVED_NEWS = "cineflash/saved-news/v1";
const KEY_WATCHLIST = "cineflash/watchlist/v1";
const KEY_REMINDERS = "cineflash/reminders/v1";
const KEY_LAST_CITY = "cineflash/last-city/v1";

/* ---------- Notizie salvate ---------- */

export interface SavedNewsItem extends NewsItem {
  savedAt: string;
}

async function loadSavedNews(): Promise<SavedNewsItem[]> {
  try {
    const raw = await AsyncStorage.getItem(KEY_SAVED_NEWS);
    if (raw) return JSON.parse(raw) as SavedNewsItem[];
  } catch {}
  return [];
}

async function persistSaved(list: SavedNewsItem[]): Promise<void> {
  await AsyncStorage.setItem(KEY_SAVED_NEWS, JSON.stringify(list));
}

/* ---------- Watchlist film ---------- */

export interface WatchlistEntry {
  /** id TMDB/iTunes come stringa. */
  id: string;
  title: string;
  posterPath: string | null;
  addedAt: string;
}

async function loadWatchlist(): Promise<WatchlistEntry[]> {
  try {
    const raw = await AsyncStorage.getItem(KEY_WATCHLIST);
    if (raw) return JSON.parse(raw) as WatchlistEntry[];
  } catch {}
  return [];
}

async function persistWatchlist(list: WatchlistEntry[]): Promise<void> {
  await AsyncStorage.setItem(KEY_WATCHLIST, JSON.stringify(list));
}

/* ---------- Promemoria uscita film ---------- */

export interface ReleaseReminder {
  movieId: string;
  title: string;
  /** ISO date dell'uscita. */
  releaseDate: string;
  createdAt: string;
}

async function loadReminders(): Promise<ReleaseReminder[]> {
  try {
    const raw = await AsyncStorage.getItem(KEY_REMINDERS);
    if (raw) return JSON.parse(raw) as ReleaseReminder[];
  } catch {}
  return [];
}

async function persistReminders(list: ReleaseReminder[]): Promise<void> {
  await AsyncStorage.setItem(KEY_REMINDERS, JSON.stringify(list));
}

/* ---------- Ultima città di prenotazione ---------- */

export async function loadLastCity(): Promise<string | null> {
  try {
    return await AsyncStorage.getItem(KEY_LAST_CITY);
  } catch {
    return null;
  }
}

export async function saveLastCity(city: string): Promise<void> {
  try {
    await AsyncStorage.setItem(KEY_LAST_CITY, city.trim());
  } catch {}
}

/* ---------- Hook: notizie salvate ---------- */

export function useSavedNews() {
  const [saved, setSaved] = useState<SavedNewsItem[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    loadSavedNews().then((list) => {
      setSaved(list);
      setReady(true);
    });
  }, []);

  const toggle = useCallback(async (item: NewsItem): Promise<boolean> => {
    const cur = await loadSavedNews();
    const exists = cur.some((x) => x.id === item.id);
    const next = exists
      ? cur.filter((x) => x.id !== item.id)
      : [{ ...item, savedAt: new Date().toISOString() }, ...cur];
    await persistSaved(next);
    setSaved(next);
    Haptics.notificationAsync(
      exists ? Haptics.NotificationFeedbackType.Warning : Haptics.NotificationFeedbackType.Success
    );
    return !exists;
  }, []);

  const isSaved = useCallback(
    (id: string) => saved.some((x) => x.id === id),
    [saved]
  );

  const clear = useCallback(async () => {
    await persistSaved([]);
    setSaved([]);
  }, []);

  return { saved, ready, toggle, isSaved, clear };
}

/* ---------- Hook: promemoria uscita ---------- */

export function useReminders() {
  const [list, setList] = useState<ReleaseReminder[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    loadReminders().then((l) => {
      setList(l);
      setReady(true);
    });
  }, []);

  const toggle = useCallback(
    async (entry: Omit<ReleaseReminder, "createdAt">): Promise<boolean> => {
      const cur = await loadReminders();
      const exists = cur.some((x) => x.movieId === entry.movieId);
      const next = exists
        ? cur.filter((x) => x.movieId !== entry.movieId)
        : [...cur, { ...entry, createdAt: new Date().toISOString() }];
      await persistReminders(next);
      setList(next);
      return !exists;
    },
    []
  );

  const has = useCallback(
    (movieId: string | number) => list.some((x) => x.movieId === String(movieId)),
    [list]
  );

  return { list, ready, toggle, has };
}

/* ---------- Hook: watchlist ---------- */

export function useWatchlist() {
  const [list, setList] = useState<WatchlistEntry[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    loadWatchlist().then((l) => {
      setList(l);
      setReady(true);
    });
  }, []);

  const toggle = useCallback(
    async (entry: Omit<WatchlistEntry, "addedAt">): Promise<boolean> => {
      const cur = await loadWatchlist();
      const exists = cur.some((x) => x.id === entry.id);
      const next = exists
        ? cur.filter((x) => x.id !== entry.id)
        : [{ ...entry, addedAt: new Date().toISOString() }, ...cur];
      await persistWatchlist(next);
      setList(next);
      Haptics.notificationAsync(
        exists ? Haptics.NotificationFeedbackType.Warning : Haptics.NotificationFeedbackType.Success
      );
      return !exists;
    },
    []
  );

  const isIn = useCallback(
    (id: string | number) => list.some((x) => x.id === String(id)),
    [list]
  );

  const clear = useCallback(async () => {
    await persistWatchlist([]);
    setList([]);
  }, []);

  return { list, ready, toggle, isIn, clear };
}
