import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  FlatList,
  Linking,
  Platform,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from "react-native";
import * as Haptics from "expo-haptics";
import { GlassView } from "expo-glass-effect";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { theme, fonts } from "../../src/theme";
import { styles as s } from "../../src/theme";
import { useStoreContext } from "../../src/storage/StoreContext";
import { loadMoviesCache, saveMoviesCache } from "../../src/storage/store";
import {
  fetchMovieDetails,
  fetchNowPlaying,
  fetchPopular,
  fetchUpcoming,
  fmtReleaseDate,
  posterUrl,
} from "../../src/logic/tmdb";
import {
  fetchItunesMovies,
  fetchItunesNewReleases,
  searchItunesMovies,
  ParsedMovie,
} from "../../src/logic/itunes";
import { Movie } from "../../src/models/types";
import { Badge, EmptyState, ModalSheet, Poster, Button, TextInput } from "../../src/components/ui";
import { TrailerPlayer } from "../../src/components/TrailerPlayer";
import { useRouter } from "expo-router";

type TabKey = "now" | "upcoming" | "popular";

const TMDB_TABS: { key: TabKey; label: string; icon: string }[] = [
  { key: "now", label: "Ora al cinema", icon: "🍿" },
  { key: "upcoming", label: "In uscita", icon: "📅" },
  { key: "popular", label: "Popolari", icon: "🔥" },
];

export default function MoviesScreen() {
  const { settings, watchlist } = useStoreContext();
  const apiKey = settings.tmdbApiKey;
  const router = useRouter();
  const insets = useSafeAreaInsets();

  const [tab, setTab] = useState<TabKey>("now");
  const [now, setNow] = useState<Movie[]>([]);
  const [upcoming, setUpcoming] = useState<Movie[]>([]);
  const [popular, setPopular] = useState<Movie[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // ricerca (iTunes, sempre disponibile)
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Movie[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [savedOnly, setSavedOnly] = useState(false);

  const [detail, setDetail] = useState<
    (Movie & {
      trailerUrl?: string | null;
      runtime?: number | null;
      genres?: string[];
      itunesUrl?: string | null;
      previewUrl?: string | null;
    }) | null
  >(null);
  const [detailLoading, setDetailLoading] = useState(false);

  const data = useMemo(() => {
    const base = results ?? (tab === "now" ? now : tab === "upcoming" ? upcoming : popular);
    return savedOnly ? base.filter((m) => watchlist.isIn(m.id)) : base;
  }, [results, tab, now, upcoming, popular, savedOnly, watchlist]);

  /* ---------- TMDB (con chiave) ---------- */
  const loadTmdb = useCallback(
    async (force = false) => {
      if (!apiKey) return;
      setError(null);
      try {
        if (!force) {
          const cached = await loadMoviesCache();
          if (cached && cached.provider === "tmdb") {
            setNow(cached.nowPlaying);
            setUpcoming(cached.upcoming);
            setPopular(cached.popular);
            setLoading(false);
          }
        }
        const [np, up, pop] = await Promise.all([
          fetchNowPlaying(apiKey),
          fetchUpcoming(apiKey),
          fetchPopular(apiKey),
        ]);
        setNow(np);
        setUpcoming(up);
        setPopular(pop);
        await saveMoviesCache({
          fetchedAt: new Date().toISOString(),
          provider: "tmdb",
          nowPlaying: np,
          upcoming: up,
          popular: pop,
        });
      } catch (e) {
        setError(e instanceof Error ? e.message : "Errore TMDB");
      } finally {
        setLoading(false);
        setRefreshing(false);
      }
    },
    [apiKey]
  );

  /* ---------- iTunes (senza chiave) ---------- */
  const loadItunes = useCallback(async () => {
    setError(null);
    try {
      const cached = await loadMoviesCache();
      if (cached && cached.provider === "itunes") {
        setNow(cached.nowPlaying);
        setUpcoming(cached.upcoming);
        setLoading(false);
      }
      const [newReleases, storeMovies] = await Promise.all([
        fetchItunesNewReleases("it"),
        fetchItunesMovies("it"),
      ]);
      // "now" = nuovi arrivi (o store se il feed RSS è vuoto)
      const nowList = newReleases.length > 0 ? newReleases : storeMovies;
      setNow(nowList);
      // "upcoming" = altri titoli recenti dallo store
      const seenIds = new Set(nowList.map((m) => m.id));
      setUpcoming(storeMovies.filter((m) => !seenIds.has(m.id)));
      setPopular([]);
      await saveMoviesCache({
        fetchedAt: new Date().toISOString(),
        provider: "itunes",
        nowPlaying: nowList,
        upcoming: storeMovies.filter((m) => !seenIds.has(m.id)),
        popular: [],
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Errore iTunes");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    if (apiKey) loadTmdb(false);
    else loadItunes();
  }, [apiKey, loadTmdb, loadItunes]);

  const onRefresh = () => {
    setRefreshing(true);
    if (apiKey) loadTmdb(true);
    else loadItunes();
  };

  const runSearch = async () => {
    const q = query.trim();
    if (q.length < 2) return;
    setSearching(true);
    setError(null);
    try {
      setResults(await searchItunesMovies(q));
    } catch {
      setError("Ricerca non riuscita, riprova.");
    } finally {
      setSearching(false);
    }
  };

  const clearSearch = () => {
    setQuery("");
    setResults(null);
  };

  const openDetail = async (movie: Movie) => {
    Haptics.selectionAsync();
    setDetail(movie);
    if (apiKey) {
      setDetailLoading(true);
      try {
        const d = await fetchMovieDetails(apiKey, movie.id);
        setDetail((prev) => (prev && prev.id === movie.id ? { ...prev, ...d } : prev));
      } catch {
        // dettagli opzionali
      } finally {
        setDetailLoading(false);
      }
    }
  };

  const openTrailer = async () => {
    if (detail?.trailerUrl) {
      try {
        await Linking.openURL(detail.trailerUrl);
      } catch {}
    }
  };

  const openItunes = async () => {
    if (detail?.itunesUrl) {
      try {
        await Linking.openURL(detail.itunesUrl);
      } catch {}
    }
  };

  const searchReviews = async () => {
    if (detail) {
      try {
        await Linking.openURL(
          `https://www.google.com/search?q=${encodeURIComponent(`recensione ${detail.title} film`)}`
        );
      } catch {}
    }
  };

  /** Apre la pagina AI con la trama del film come contesto. */
  const explainWithAI = async () => {
    if (!detail) return;
    Haptics.selectionAsync();
    const parts = [
      detail.overview ? `Trama: ${detail.overview}` : "",
      detail.genres?.length ? `Generi: ${detail.genres.join(", ")}.` : "",
      detail.voteAverage > 0 ? `Voto: ${detail.voteAverage.toFixed(1)}/10.` : "",
      detail.releaseDate ? `Uscita: ${fmtReleaseDate(detail.releaseDate)}.` : "",
    ].filter(Boolean);
    setDetail(null);
    router.push({
      pathname: "/ai",
      params: {
        mode: "movie",
        title: detail.title,
        text: parts.length > 0 ? parts.join(" ") : `Film: ${detail.title}.`,
      },
    });
  };

  const showTabs = !results && (apiKey ? true : now.length > 0 || upcoming.length > 0);

  return (
    <View style={s.screen}>
      <FlatList
        data={data}
        keyExtractor={(m) => String(m.id)}
        numColumns={2}
        columnWrapperStyle={styles.gridRow}
        contentContainerStyle={{ paddingBottom: 32 + insets.bottom }}
        ListHeaderComponent={
          <View style={[styles.header, { paddingTop: 16 + insets.top }]}>
            {/* Masthead coerente con la home: occhiello + titolo serif */}
            <Text style={s.eyebrow}>CineFlash · Catalogo</Text>
            <Text style={styles.masthead}>Film</Text>
            {!apiKey && (
              <Text style={styles.modeHint}>
                Modalità senza chiave: dati e trailer da Apple iTunes. Puoi
                attivare TMDB dalle Impostazioni per i cataloghi completi.
              </Text>
            )}

            {/* Ricerca */}
            <View style={[s.row, { marginTop: 10 }]}>
              <View style={s.grow}>
                <TextInput
                  value={query}
                  onChangeText={setQuery}
                  placeholder="Cerca un film…"
                  autoCapitalize="sentences"
                />
              </View>
              <Pressable
                onPress={() => {
                  Haptics.selectionAsync();
                  runSearch();
                }}
              >
                <GlassView glassEffectStyle="clear" isInteractive style={styles.searchBtnGlass}>
                  <Text style={styles.searchBtnText}>🔍</Text>
                </GlassView>
              </Pressable>
              {results && (
                <Pressable onPress={clearSearch}>
                  <GlassView glassEffectStyle="clear" isInteractive style={styles.searchBtnGlass}>
                    <Text style={styles.searchBtnText}>✕</Text>
                  </GlassView>
                </Pressable>
              )}
            </View>

            {showTabs && (
              <View style={[s.row, { marginTop: 12, flexWrap: "wrap" }]}>
                {TMDB_TABS.filter((t) => (apiKey ? true : t.key !== "popular")).map((t) => (
                  <Pressable
                    key={t.key}
                    onPress={() => {
                      Haptics.selectionAsync();
                      clearSearch();
                      setSavedOnly(false);
                      setTab(t.key);
                    }}
                  >
                    {tab === t.key && !savedOnly ? (
                      <View style={[styles.seg, styles.segOn]}>
                        <Text style={[styles.segText, styles.segTextOn]}>{t.icon} {t.label}</Text>
                      </View>
                    ) : (
                      <GlassView glassEffectStyle="clear" isInteractive style={styles.segGlass}>
                        <Text style={styles.segText}>{t.icon} {t.label}</Text>
                      </GlassView>
                    )}
                  </Pressable>
                ))}
                <Pressable
                  onPress={() => {
                    Haptics.selectionAsync();
                    clearSearch();
                    setSavedOnly((v) => !v);
                  }}
                >
                  {savedOnly ? (
                    <View style={[styles.seg, styles.segOn]}>
                      <Text style={[styles.segText, styles.segTextOn]}>
                        ⭐ Preferiti ({watchlist.list.length})
                      </Text>
                    </View>
                  ) : (
                    <GlassView glassEffectStyle="clear" isInteractive style={[styles.segGlass, styles.segStar]}>
                      <Text style={styles.segText}>⭐ Preferiti ({watchlist.list.length})</Text>
                    </GlassView>
                  )}
                </Pressable>
              </View>
            )}

            {results && (
              <Text style={styles.resultCount}>
                {results.length} risultat{results.length === 1 ? "o" : "i"} per “{query.trim()}”
              </Text>
            )}
            {error ? <Text style={styles.error}>{error}</Text> : null}
          </View>
        }
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={theme.colors.accent}
          />
        }
        renderItem={({ item }) => (
          <Pressable
            onPress={() => openDetail(item)}
            style={({ pressed }) => [styles.posterCard, pressed && { opacity: 0.75 }]}
          >
            <View>
              <Poster uri={posterUrl(item.posterPath)} style={styles.poster} />
              <Pressable
                onPress={() =>
                  watchlist.toggle({
                    id: String(item.id),
                    title: item.title,
                    posterPath: item.posterPath,
                  })
                }
                hitSlop={6}
              >
                <GlassView
                  glassEffectStyle="clear"
                  isInteractive
                  tintColor={watchlist.isIn(item.id) ? theme.colors.accent : undefined}
                  style={styles.starBtn}
                >
                  <Text style={styles.starText}>{watchlist.isIn(item.id) ? "⭐" : "☆"}</Text>
                </GlassView>
              </Pressable>
            </View>
            <Text style={styles.posterTitle} numberOfLines={2}>
              {item.title}
            </Text>
            <View style={[s.row, { marginTop: 4 }]}>
              {item.voteAverage > 0 ? (
                <Text style={styles.vote}>⭐ {item.voteAverage.toFixed(1)}</Text>
              ) : null}
              <View style={s.grow} />
              <Text style={styles.date} numberOfLines={1}>
                {item.releaseDate ? fmtReleaseDate(item.releaseDate).replace(/ \d{4}$/, "") : ""}
              </Text>
            </View>
          </Pressable>
        )}
        ListEmptyComponent={
          loading ? (
            <ActivityIndicator color={theme.colors.accent} style={{ padding: 40 }} />
          ) : searching ? (
            <ActivityIndicator color={theme.colors.accent} style={{ padding: 40 }} />
          ) : results ? (
            <EmptyState icon="🔍" title="Nessun risultato" subtitle="Prova con un altro titolo." />
          ) : (
            <EmptyState
              icon="🎞️"
              title="Nessun film"
              subtitle="Riprova con l'aggiornamento (tira giù la lista)."
            />
          )
        }
      />

      {/* Dettaglio film */}
      <ModalSheet visible={detail != null} onClose={() => setDetail(null)} title={detail?.title ?? ""}>
        {detail && (
          <View>
            <View style={s.row}>
              <Poster uri={posterUrl(detail.posterPath, "w500")} style={styles.detailPoster} />
              <View style={[s.grow, { marginLeft: 14 }]}>
                {detail.voteAverage > 0 && <Badge label={`⭐ ${detail.voteAverage.toFixed(1)}/10`} tone="accent" />}
                <Text style={styles.detailDate}>{fmtReleaseDate(detail.releaseDate)}</Text>
                {detail.runtime ? <Text style={styles.detailMeta}>{detail.runtime} min</Text> : null}
                {detail.genres && detail.genres.length > 0 ? (
                  <Text style={styles.detailMeta} numberOfLines={2}>
                    {detail.genres.join(" · ")}
                  </Text>
                ) : null}
              </View>
            </View>

            {detailLoading && (
              <View style={[s.row, { marginTop: 12 }]}>
                <ActivityIndicator color={theme.colors.accent} size="small" />
                <Text style={styles.detailMeta}> carico i dettagli…</Text>
              </View>
            )}

            {/* Trailer in-app: video nativo (Apple) o embed YouTube */}
            <TrailerPlayer
              youtubeUrl={detail.trailerUrl}
              mp4Url={detail.previewUrl ?? null}
              style={styles.trailer}
            />

            <Text style={styles.overview}>
              {detail.overview || "Trama non disponibile per questo film."}
            </Text>

            <View style={{ marginTop: 12 }}>
              {!settings.aiDisabled && (
                <Button label="✨  Spiega con l'AI" variant="primary" onPress={explainWithAI} />
              )}
              <Button
                label={
                  watchlist.isIn(detail.id)
                    ? "✓  Nella watchlist — tocca per rimuovere"
                    : "☆  Aggiungi alla watchlist"
                }
                variant="ghost"
                onPress={() =>
                  watchlist.toggle({
                    id: String(detail.id),
                    title: detail.title,
                    posterPath: detail.posterPath,
                  })
                }
              />
              <Button label="🔍 Leggi le recensioni" onPress={searchReviews} variant="ghost" />
              {detail.itunesUrl ? (
                <Button label="🍎 Apri in iTunes Store" onPress={openItunes} variant="ghost" />
              ) : null}
            </View>
          </View>
        )}
      </ModalSheet>
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: 16,
    paddingTop: 16,
    paddingBottom: 14,
  },
  masthead: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 34,
    fontWeight: "700",
    letterSpacing: -0.5,
    lineHeight: 40,
    marginTop: 6,
  },
  modeHint: { color: theme.colors.textDim, fontSize: 12, lineHeight: 17, marginTop: 4 },
  modeLink: { color: theme.colors.accent, fontWeight: "700" },
  error: { color: theme.colors.warn, fontSize: 12, marginTop: 8 },
  searchBtnGlass: {
    width: 44,
    height: 44,
    marginLeft: 8,
    borderRadius: theme.radius.sm,
    alignItems: "center" as const,
    justifyContent: "center" as const,
    ...Platform.select({
      ios: {},
      default: {
        backgroundColor: "rgba(255,255,255,0.10)",
        borderWidth: StyleSheet.hairlineWidth,
        borderColor: theme.colors.border,
      },
    }),
  },
  searchBtnText: { fontSize: 15, color: theme.colors.text },
  resultCount: { color: theme.colors.textDim, fontSize: 12, marginTop: 10, fontWeight: "700" },
  seg: {
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 999,
    marginRight: 8,
  },
  segGlass: {
    borderRadius: 999,
    marginRight: 8,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: "rgba(255,255,255,0.14)",
    ...Platform.select({
      ios: {},
      default: { backgroundColor: "rgba(255,255,255,0.10)" },
    }),
  },
  segOn: { backgroundColor: theme.colors.accent },
  segText: {
    color: theme.colors.textDim,
    fontSize: 13,
    fontWeight: "600",
    paddingHorizontal: 12,
    paddingVertical: 7,
  },
  segTextOn: { color: theme.colors.bg, fontWeight: "800" },
  gridRow: { justifyContent: "space-between", paddingHorizontal: 16, marginTop: 14 },
  posterCard: { width: "48.5%" },
  trailer: {
    width: "100%",
    aspectRatio: 16 / 9,
    borderRadius: theme.radius.sm,
    marginTop: 12,
    backgroundColor: "#000",
  },
  starBtn: {
    position: "absolute",
    top: 6,
    right: 6,
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: "center" as const,
    justifyContent: "center" as const,
    ...Platform.select({
      ios: {},
      default: {
        backgroundColor: "rgba(10,10,15,0.65)",
        borderWidth: 1,
        borderColor: theme.colors.accent + "66",
      },
    }),
  },
  starText: { fontSize: 16 },
  segStar: { borderColor: theme.colors.accent + "66" },
  poster: {
    width: "100%",
    aspectRatio: 2 / 3,
    borderRadius: theme.radius.sm,
  },
  posterTitle: {
    color: theme.colors.text,
    fontSize: 13,
    fontWeight: "600",
    marginTop: 8,
    lineHeight: 17,
  },
  vote: { color: theme.colors.accent, fontSize: 12, fontWeight: "800" },
  date: { color: theme.colors.textDim, fontSize: 11, flexShrink: 1, fontVariant: ["tabular-nums"] },
  detailPoster: {
    width: 110,
    aspectRatio: 2 / 3,
    borderRadius: theme.radius.sm,
  },
  detailDate: { color: theme.colors.text, fontSize: 13, fontWeight: "700", marginTop: 8 },
  detailMeta: { color: theme.colors.textDim, fontSize: 12, marginTop: 4 },
  overview: {
    color: theme.colors.textDim,
    fontSize: 14,
    lineHeight: 21,
    marginTop: 14,
  },
});
