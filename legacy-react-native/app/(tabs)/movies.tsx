import React, { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Animated,
  FlatList,
  Linking,
  Platform,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
  ViewStyle,
} from "react-native";
import * as Haptics from "expo-haptics";
import { GlassView } from "expo-glass-effect";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Reveal, SPRING, usePressScale, useMagnetism } from "../../src/motion";

/** Pressable interno trasparente: porta solo i gesti, lo stile vive sull'Animated.View. */
const stCardPress: ViewStyle = { flex: 1 };
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
import { ScreenHeader } from "../../src/components/ScreenHeader";
import { SkeletonPosterCard } from "../../src/components/Skeletons";
import * as MediaLibrary from "expo-media-library";
import * as FileSystem from "expo-file-system";
import { File } from "expo-file-system";
import { useFocusEffect } from "expo-router";
import { TrailerPlayer } from "../../src/components/TrailerPlayer";
import {
  applyCuration,
  isAlreadyReleased,
  loadCuration,
  CurationState,
} from "../../src/logic/movieCuration";
import { useRouter } from "expo-router";

type TabKey = "now" | "upcoming" | "popular";

const DATA_OGGI = new Intl.DateTimeFormat("it-IT", {
  weekday: "long",
  day: "numeric",
  month: "long",
});

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
  /** Ordinamento della griglia (fuori dalla ricerca). */
  const [sortBy, setSortBy] = useState<"none" | "vote" | "date" | "title">("none");
  /** Vista: film recenti (default) o tutti (inclusi i già usciti). */
  const [scope, setScope] = useState<"recent" | "all">("recent");
  /** Decisioni della redazione AI (da /ai-dashboard). */
  const [curation, setCuration] = useState<CurationState>({
    promoted: [],
    hidden: [],
    generatedAt: null,
    note: null,
  });

  // Ricarica la curation ogni volta che la tab torna in primo piano
  // (dopo un'applica dalla Dashboard AI).
  useFocusEffect(
    useCallback(() => {
      loadCuration().then(setCuration).catch(() => {});
    }, [])
  );

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
  /** true quando il poster del dettaglio corrente è stato salvato in fototeca. */
  const [posterSaved, setPosterSaved] = useState(false);

  const data = useMemo(() => {
    const base = results ?? (tab === "now" ? now : tab === "upcoming" ? upcoming : popular);
    let list = results ? base : applyCuration(base, curation);
    if (scope === "recent" && !results) {
      // Nella vista recente restano le uscite di qui in poi (con 7 giorni di
      // grazia per i film usciti da poco): i già usciti vivono in "Tutti".
      list = list.filter((m) => !isAlreadyReleased(m.releaseDate));
    }
    if (savedOnly) list = list.filter((m) => watchlist.isIn(m.id));
    if (sortBy === "vote") {
      list = [...list].sort((a, b) => b.voteAverage - a.voteAverage);
    } else if (sortBy === "title") {
      list = [...list].sort((a, b) => a.title.localeCompare(b.title, "it"));
    } else if (sortBy === "date") {
      list = [...list].sort((a, b) => {
        const da = a.releaseDate ? Date.parse(a.releaseDate) : Infinity;
        const db = b.releaseDate ? Date.parse(b.releaseDate) : Infinity;
        return da - db;
      });
    }
    return list;
  }, [results, tab, now, upcoming, popular, savedOnly, watchlist, sortBy, scope, curation]);

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

  const runSearch = async (q?: string) => {
    const term = (q ?? query).trim();
    if (term.length < 2) return;
    setSearching(true);
    setError(null);
    try {
      setResults(await searchItunesMovies(term));
    } catch {
      setError("Ricerca non riuscita, riprova.");
    } finally {
      setSearching(false);
    }
  };

  /* Ricerca live: 600ms dopo l'ultimo tasto la query parte da sola.
  Lo store ancora aperto usa la vecchia search manuale (bottone 🔍). */
  useEffect(() => {
    const term = query.trim();
    if (term.length < 2) return;
    const t = setTimeout(() => runSearch(term), 600);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query]);

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

  /** Salva il poster in fototeca: chiede il permesso solo al primo uso. */
  const savePosterToLibrary = async () => {
    if (!detail?.posterPath) return;
    Haptics.selectionAsync();
    try {
      const perm = await MediaLibrary.requestPermissionsAsync();
      if (!perm.granted) {
        Alert.alert(
          "Permesso fototeca",
          "Per salvare il poster, consenti l'accesso alla fototeca dalle Impostazioni di sistema.",
          [
            { text: "Annulla", style: "cancel" },
            { text: "Apri Impostazioni", onPress: () => Linking.openSettings().catch(() => {}) },
          ]
        );
        return;
      }
      setPosterSaved(false);
      // SDK 58: API a classi — scarico su un file temporaneo in cache e poi
      // lo sposto in fototeca con MediaLibrary.
      const dest = new File(FileSystem.Paths.cache, `poster-${detail.id}.jpg`);
      const file = await File.downloadFileAsync(
        posterUrl(detail.posterPath, "w780") ?? detail.posterPath,
        dest,
        { idempotent: true }
      );
      await MediaLibrary.createAssetAsync(file.uri);
      file.delete();
      setPosterSaved(true);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    } catch {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
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
            {/* Masthead condiviso: occhiello + titolo serif */}
            <ScreenHeader
              eyebrow={DATA_OGGI.format(new Date())}
              title="Catalogo"
              right={
                <Pressable
                  onPress={() => {
                    Haptics.selectionAsync();
                    router.push("/settings");
                  }}
                  hitSlop={8}
                >
                  <View style={styles.gearBtn}>
                    <Text style={styles.gearIcon}>⚙</Text>
                  </View>
                </Pressable>
              }
            />

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
                {/* Ambito: recenti (default) o tutti (anche già usciti) */}
                <Pressable
                  onPress={() => {
                    Haptics.selectionAsync();
                    setScope((v) => (v === "recent" ? "all" : "recent"));
                  }}
                >
                  <View style={[styles.sortChip, scope === "all" && styles.sortChipOn]}>
                    <Text
                      style={[
                        styles.sortChipText,
                        scope === "all" && styles.sortChipTextOn,
                      ]}
                    >
                      📀 Includi già usciti
                    </Text>
                  </View>
                </Pressable>
                {/* Ordinamento */}
                {(
                  [
                    { key: "none", label: "•" },
                    { key: "vote", label: "⭐ Voto" },
                    { key: "date", label: "📅 Uscita" },
                    { key: "title", label: "A–Z" },
                  ] as const
                ).map((o) => (
                  <Pressable
                    key={o.key}
                    onPress={() => {
                      Haptics.selectionAsync();
                      setSortBy(o.key);
                    }}
                  >
                    <View style={[styles.sortChip, sortBy === o.key && styles.sortChipOn]}>
                      <Text
                        style={[
                          styles.sortChipText,
                          sortBy === o.key && styles.sortChipTextOn,
                        ]}
                      >
                        {o.label}
                      </Text>
                    </View>
                  </Pressable>
                ))}
              </View>
            )}

            {showTabs && (
              <View style={[s.row, { marginTop: 8, flexWrap: "wrap" }]}>
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
          <MovieCard
            item={item}
            starred={watchlist.isIn(item.id)}
            onPress={openDetail}
            onToggleStar={() =>
              watchlist.toggle({
                id: String(item.id),
                title: item.title,
                posterPath: item.posterPath,
              })
            }
          />
        )}
        ListEmptyComponent={
          loading || searching ? (
            <View style={styles.skeletonGrid}>
              {[0, 1, 2, 3, 4, 5].map((i) => (
                <SkeletonPosterCard key={i} />
              ))}
            </View>
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
            {!detail.trailerUrl && !detail.previewUrl && !detailLoading ? (
              <Text style={styles.noTrailerHint}>
                Trailer non disponibile per questo titolo: lo trovi sulla sua
                scheda TMDB o sul canale ufficiale del film.
              </Text>
            ) : null}

            <Text style={styles.overview}>
              {detail.overview || "Trama non disponibile per questo film."}
            </Text>

            <View style={{ marginTop: 12 }}>
              <Button label="✨  Spiega con l'AI" variant="primary" onPress={explainWithAI} />
              {detail.posterPath ? (
                <Button
                  label={posterSaved ? "✓  Poster salvato in fototeca" : "🖼️  Salva il poster in fototeca"}
                  variant="ghost"
                  onPress={savePosterToLibrary}
                />
              ) : null}
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
        backgroundColor: theme.colors.surfaceAlt,
        borderWidth: StyleSheet.hairlineWidth,
        borderColor: theme.colors.border,
      },
    }),
  },
  searchBtnText: { fontSize: 15, color: theme.colors.text },
  gearBtn: {
    width: 30,
    height: 30,
    borderRadius: 15,
    alignItems: "center",
    justifyContent: "center",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    backgroundColor: theme.colors.surfaceAlt,
  },
  gearIcon: { fontSize: 13, color: theme.colors.textDim },
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
    borderColor: theme.colors.border,
    ...Platform.select({
      ios: {},
      default: { backgroundColor: theme.colors.surfaceAlt },
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
  segTextOn: { color: theme.colors.onAccent, fontWeight: "800" },
  gridRow: { justifyContent: "space-between", paddingHorizontal: 16, marginTop: 14 },
  posterCard: { width: "48.5%" },
  skeletonGrid: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 12,
    paddingHorizontal: 16,
    marginTop: 14,
  },
  trailer: {
    width: "100%",
    aspectRatio: 16 / 9,
    borderRadius: theme.radius.sm,
    marginTop: 12,
    backgroundColor: "#000",
  },
  voteBadge: {
    position: "absolute",
    top: 6,
    left: 6,
    backgroundColor: "rgba(10,10,15,0.82)",
    borderWidth: 1,
    borderColor: theme.colors.accent + "55",
    borderRadius: 8,
    paddingHorizontal: 6,
    paddingVertical: 2,
  },
  voteBadgeText: {
    color: theme.colors.accent,
    fontSize: 10,
    fontWeight: "800",
    fontVariant: ["tabular-nums"],
  },
  sortChip: {
    paddingHorizontal: 11,
    paddingVertical: 5,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    backgroundColor: theme.colors.surfaceAlt,
    marginRight: 6,
  },
  sortChipOn: {
    backgroundColor: theme.colors.accent,
    borderColor: theme.colors.accent,
  },
  sortChipText: { color: theme.colors.textDim, fontSize: 11, fontWeight: "700" },
  sortChipTextOn: { color: theme.colors.onAccent, fontWeight: "800" },
  soonRibbon: {
    position: "absolute",
    bottom: 6,
    left: 6,
    backgroundColor: "rgba(10,10,15,0.82)",
    borderWidth: 1,
    borderColor: theme.colors.accent + "55",
    borderRadius: 6,
    paddingHorizontal: 6,
    paddingVertical: 2,
  },
  soonRibbonText: {
    color: theme.colors.accent,
    fontSize: 9,
    fontWeight: "800",
    letterSpacing: 0.8,
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
  date: {
    color: theme.colors.textDim,
    fontSize: 10,
    flexShrink: 1,
    fontVariant: ["tabular-nums"],
  },
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
  noTrailerHint: {
    color: theme.colors.textDim,
    fontSize: 12,
    lineHeight: 17,
    marginTop: 8,
    fontStyle: "italic",
  },
});

/* ================================================================== */
/* MovieCard — card poster memoizzata con pop a molla all'ingresso e   */
/* press-scale. Estratta dal renderItem: senza memo, ogni stella o     */
/* ricerca ridisegnata disegnava l'intera griglia.                     */
/* ================================================================== */

/**
 * Nastro di stato sul poster: IN ARRIVO se l'uscita è futura (entro 60 giorni),
 * IN USCITA se è uscito negli ultimi 7 giorni. null = nessun nastro.
 */
function statusRibbon(releaseDate: string | null): string | null {
  if (!releaseDate) return null;
  const d = new Date(releaseDate);
  if (isNaN(d.getTime())) return null;
  const diffDays = Math.ceil((d.getTime() - Date.now()) / 86_400_000);
  if (diffDays > 0 && diffDays <= 60) return "IN ARRIVO";
  if (diffDays <= 0 && diffDays >= -7) return "IN USCITA";
  return null;
}

type CardProps = {
  item: Movie;
  starred: boolean;
  onPress: (m: Movie) => void;
  onToggleStar: () => void;
};

const MovieCard = memo(function MovieCard({ item, starred, onPress, onToggleStar }: CardProps) {
  const pop = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    Animated.spring(pop, { toValue: 1, ...SPRING.cinematic, useNativeDriver: true }).start();
  }, [pop]);
  const press = usePressScale(0.95);
  const tilt = useMagnetism(3);

  const style = {
    opacity: pop,
    transform: [
      ...press.style.transform,
      { translateY: pop.interpolate({ inputRange: [0, 1], outputRange: [24, 0] }) },
      { scale: pop.interpolate({ inputRange: [0, 1], outputRange: [0.92, 1] }) },
    ],
  };

  return (
    <Animated.View style={[styles.posterCard, style]}>
    <Pressable
      onPress={() => onPress(item)}
      onPressIn={press.onPressIn}
      onPressOut={press.onPressOut}
      style={stCardPress}
    >
      <View>
        <Poster uri={posterUrl(item.posterPath)} style={styles.poster} />
        {item.voteAverage > 0 ? (
          <View style={styles.voteBadge}>
            <Text style={styles.voteBadgeText}>{item.voteAverage.toFixed(1)}</Text>
          </View>
        ) : null}
        {statusRibbon(item.releaseDate) ? (
          <View style={styles.soonRibbon}>
            <Text style={styles.soonRibbonText}>{statusRibbon(item.releaseDate)}</Text>
          </View>
        ) : null}
        <Pressable
          onPress={onToggleStar}
          onPressIn={tilt.onPressIn}
          onPressOut={tilt.onPressOut}
          hitSlop={6}
        >
          <GlassView
            glassEffectStyle="clear"
            isInteractive
            tintColor={starred ? theme.colors.accent : undefined}
            style={styles.starBtn}
          >
            <Text style={styles.starText}>{starred ? "⭐" : "☆"}</Text>
          </GlassView>
        </Pressable>
      </View>
      <Text style={styles.posterTitle} numberOfLines={2}>
        {item.title}
      </Text>
      <View style={[s.row, { marginTop: 4 }]}>
        {item.voteAverage > 0 ? <Text style={styles.vote}>⭐ {item.voteAverage.toFixed(1)}</Text> : null}
        <View style={s.grow} />
        <Text style={styles.date} numberOfLines={1}>
          {item.releaseDate ? fmtReleaseDate(item.releaseDate) : ""}
        </Text>
      </View>
    </Pressable>
    </Animated.View>
  );
});
