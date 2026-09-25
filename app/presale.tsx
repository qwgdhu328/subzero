import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  FlatList,
  Image,
  Linking,
  Platform,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { GlassView } from "expo-glass-effect";
import { LinearGradient } from "expo-linear-gradient";
import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { theme, fonts } from "../src/theme";
import { styles as s } from "../src/theme";
import { useStoreContext } from "../src/storage/StoreContext";
import {
  loadMoviesCache,
  saveMoviesCache,
  loadSettings,
} from "../src/storage/store";
import { fetchUpcoming, posterUrl, fmtReleaseDate } from "../src/logic/tmdb";
import {
  fetchItunesNewReleases,
  fetchItunesMovies,
} from "../src/logic/itunes";
import { Movie } from "../src/models/types";
import { EmptyState, Spinner } from "../src/components/ui";
import { DetailMovie, MovieDetailSheet } from "../src/components/MovieDetailSheet";
import { BookingSheet } from "../src/components/BookingSheet";

/**
 * Pagina PREVENDITE — esperienza premium:
 * film in evidenza (il più vicino all'uscita) su card editoriale con serif,
 * poi griglia di poster con badge conto alla rovescia e prenotazione rapida.
 * Prenota → scelta città → cinema reali (OSM) → sito del cinema con il film.
 */
export default function PresaleScreen() {
  const router = useRouter();
  const { title } = useLocalSearchParams<{ title?: string }>();
  const { watchlist, settings } = useStoreContext();
  const insets = useSafeAreaInsets();

  const [movies, setMovies] = useState<DetailMovie[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [detail, setDetail] = useState<DetailMovie | null>(null);
  /** Film per cui è aperto il flusso di prenotazione (città → cinema). */
  const [booking, setBooking] = useState<DetailMovie | null>(null);

  /* ---------- Catalogo film prenotabili ---------- */

  const load = useCallback(async (force = false) => {
    setError(null);
    if (!force) {
      const cached = await loadMoviesCache();
      if (cached && cached.provider === "tmdb") {
        setMovies(cached.upcoming as DetailMovie[]);
        setLoading(false);
      }
    }
    try {
      const st = await loadSettings();
      if (st.tmdbApiKey) {
        const up = await fetchUpcoming(st.tmdbApiKey);
        setMovies(up as DetailMovie[]);
        const cached = await loadMoviesCache();
        await saveMoviesCache({
          fetchedAt: new Date().toISOString(),
          provider: "tmdb",
          nowPlaying: cached?.nowPlaying ?? [],
          upcoming: up,
          popular: cached?.popular ?? [],
        });
      } else {
        const [releases, store] = await Promise.all([
          fetchItunesNewReleases("it"),
          fetchItunesMovies("it"),
        ]);
        const list = releases.length > 0 ? releases : store;
        setMovies(list as DetailMovie[]);
        const cached = await loadMoviesCache();
        await saveMoviesCache({
          fetchedAt: new Date().toISOString(),
          provider: "itunes",
          nowPlaying: cached?.nowPlaying ?? [],
          upcoming: list,
          popular: cached?.popular ?? [],
        });
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Caricamento non riuscito");
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    load(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /** Scheda film: i titoli da TMDB hanno bisogno dei dettagli (trailer ecc). */
  const openDetail = (m: Movie) => {
    Haptics.selectionAsync();
    setDetail({ ...m, needsTmdb: true });
  };

  /** Prenota direttamente dalla griglia (senza passare dalla scheda). */
  const quickBook = (m: DetailMovie) => {
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    setBooking(m);
  };

  /** Prenotazione: apre lo sheet città → cinema → sito del cinema. */
  const bookMovie = (m: DetailMovie) => {
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    setDetail(null);
    setBooking(m);
  };

  /* ---------- In evidenza: il film più vicino all'uscita ---------- */

  const featured = useMemo(() => {
    const withDays = movies
      .map((m) => ({ m, d: daysUntil(m.releaseDate) }))
      .filter((x) => x.d !== null && x.d >= -2) // già usciti da ≤2 giorni ok
      .sort((a, b) => (a.d as number) - (b.d as number));
    return (withDays[0]?.m ?? movies[0] ?? null) as DetailMovie | null;
  }, [movies]);

  const rest = useMemo(
    () => movies.filter((m) => m.id !== featured?.id),
    [movies, featured]
  );

  /* Sezioni per finestra di uscita: Oggi / Questa settimana / Più avanti */
  const sections = useMemo(() => {
    const buckets: { label: string; items: DetailMovie[] }[] = [
      { label: "IN USCITA ORA", items: [] },
      { label: "QUESTA SETTIMANA", items: [] },
      { label: "PIÙ AVANTI", items: [] },
      { label: "DATA DA DEFINIRE", items: [] },
    ];
    for (const m of rest) {
      const d = daysUntil(m.releaseDate);
      if (d === null || isNaN(d)) buckets[3].items.push(m);
      else if (d <= 0) buckets[0].items.push(m);
      else if (d <= 7) buckets[1].items.push(m);
      else buckets[2].items.push(m);
    }
    return buckets.filter((b) => b.items.length > 0);
  }, [rest]);

  /** Card singola (usata dentro le coppie della griglia). */
  const renderCard = (item: DetailMovie) => {
    const days = daysUntil(item.releaseDate);
    return (
      <Pressable
        onPress={() => openDetail(item)}
        style={({ pressed }) => [styles.card, pressed && { opacity: 0.85 }]}
      >
        <View style={styles.posterWrap}>
          <PosterImage uri={posterUrl(item.posterPath, "w342")} />
          {days !== null && days >= 0 && days <= 14 && (
            <View style={styles.soonBadge}>
              <Text style={styles.soonBadgeText}>
                {days === 0 ? "OGGI" : days === 1 ? "DOMANI" : `TRA ${days} G`}
              </Text>
            </View>
          )}
        </View>
        <Text style={styles.cardTitle} numberOfLines={2}>
          {item.title}
        </Text>
        <Text style={styles.cardDate} numberOfLines={1}>
          {fmtReleaseDate(item.releaseDate)}
        </Text>
        <Pressable
          onPress={() => quickBook(item)}
          hitSlop={6}
          style={({ pressed }) => [styles.cardBook, pressed && { opacity: 0.7 }]}
        >
          <Text style={styles.cardBookText}>PRENOTA</Text>
        </Pressable>
      </Pressable>
    );
  };

  /* Modello a righe: intestazioni di sezione + coppie di card (griglia 2 col) */
  type Row =
    | { kind: "section"; key: string; label: string; count: number }
    | { kind: "pair"; key: string; a: DetailMovie; b: DetailMovie | null };
  const listRows = useMemo<Row[]>(() => {
    const rows: Row[] = [];
    for (const sec of sections) {
      rows.push({
        kind: "section",
        key: `sec_${sec.label}`,
        label: sec.label,
        count: sec.items.length,
      });
      for (let i = 0; i < sec.items.length; i += 2) {
        rows.push({
          kind: "pair",
          key: `pair_${sec.label}_${i}`,
          a: sec.items[i],
          b: sec.items[i + 1] ?? null,
        });
      }
    }
    return rows;
  }, [sections]);

  const renderItem = ({ item }: { item: Row }) => {
    if (item.kind === "section") {
      return (
        <View style={styles.sectionHead}>
          <Text style={styles.sectionLabel}>{item.label}</Text>
          <Text style={styles.sectionCount}>{item.count}</Text>
          <View style={styles.sectionRule} />
        </View>
      );
    }
    return (
      <View style={styles.gridRow}>
        {renderCard(item.a)}
        {item.b ? (
          renderCard(item.b)
        ) : (
          <View style={[styles.card, { backgroundColor: "transparent", borderWidth: 0 }]} />
        )}
      </View>
    );
  };

  return (
    <View style={s.screen}>
      <Stack.Screen options={{ headerShown: false }} />
      <FlatList
        data={listRows}
        keyExtractor={(r) => r.key}
        renderItem={renderItem}
        contentContainerStyle={{ paddingBottom: 40 + insets.bottom }}
        ListHeaderComponent={
          <View>
            {/* Header: indietro + occhiello + titolo serif */}
            <View style={[s.row, styles.header, { paddingTop: 14 + insets.top }]}>
              <Pressable
                onPress={() => {
                  Haptics.selectionAsync();
                  router.back();
                }}
                hitSlop={10}
              >
                <GlassView
                  glassEffectStyle="clear"
                  isInteractive
                  style={styles.backBtn}
                >
                  <Text style={styles.backText}>‹</Text>
                </GlassView>
              </Pressable>
            </View>
            <View style={styles.masthead}>
              <Text style={s.eyebrow}>CineFlash · Biglietti</Text>
              <Text style={styles.pageTitle}>
                {title && title.length > 0 ? title : "Prevendite"}
              </Text>
            </View>

            {/* In evidenza */}
            {featured ? (
              <Pressable
                onPress={() => openDetail(featured)}
                style={({ pressed }) => [
                  styles.featured,
                  pressed && { opacity: 0.9 },
                ]}
              >
                <LinearGradient
                  colors={[theme.colors.surfaceRaised, theme.colors.surface]}
                  start={{ x: 0, y: 0 }}
                  end={{ x: 1, y: 1 }}
                  style={styles.featuredGrad}
                >
                  <PosterImage
                    uri={posterUrl(featured.posterPath, "w500")}
                    style={styles.featuredPoster}
                  />
                  <View style={[s.grow, styles.featuredBody]}>
                    <Text style={styles.featuredKicker}>
                      {releaseKicker(featured.releaseDate)}
                    </Text>
                    <Text style={styles.featuredTitle} numberOfLines={3}>
                      {featured.title}
                    </Text>
                    <Text style={styles.featuredDate} numberOfLines={1}>
                      {fmtReleaseDate(featured.releaseDate)}
                    </Text>
                    <Pressable
                      onPress={() => bookMovie(featured)}
                      hitSlop={6}
                      style={({ pressed }) => [
                        styles.featuredBook,
                        pressed && { opacity: 0.8 },
                      ]}
                    >
                      <Text style={styles.featuredBookText}>🎟️  Prenota ora</Text>
                    </Pressable>
                  </View>
                </LinearGradient>
              </Pressable>
            ) : null}



            {error ? <Text style={styles.error}>{error}</Text> : null}
          </View>
        }
        ListEmptyComponent={
          loading ? (
            <Spinner label="Carico i film prenotabili…" />
          ) : (
            <EmptyState
              icon="🎟️"
              title="Nessun film in prevendita"
              subtitle="Tira giù per aggiornare l'elenco dei titoli in uscita."
            />
          )
        }
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => {
              setRefreshing(true);
              load(true);
            }}
            tintColor={theme.colors.accent}
          />
        }
      />

      {/* Flusso di prenotazione: città → cinema → sito del cinema */}
      <BookingSheet
        movieTitle={booking?.title ?? null}
        onClose={() => setBooking(null)}
      />

      {/* Dettaglio film */}
      <MovieDetailSheet
        movie={detail}
        onClose={() => setDetail(null)}
        onOpenAI={(m) => {
          const parts = [
            m.overview ? `Trama: ${m.overview}` : "",
            m.genres?.length ? `Generi: ${m.genres.join(", ")}.` : "",
            m.releaseDate ? `Uscita: ${fmtReleaseDate(m.releaseDate)}.` : "",
          ].filter(Boolean);
          setDetail(null);
          router.push({
            pathname: "/ai",
            params: {
              mode: "movie",
              title: m.title,
              text: parts.length > 0 ? parts.join(" ") : `Film: ${m.title}.`,
            },
          });
        }}
        watchlist={watchlist}
        aiDisabled={settings.aiDisabled}
        onBook={bookMovie}
      />
    </View>
  );
}

/* ---------- Aiutanti ---------- */

/** Giorni mancanti all'uscita (null se data assente o invalida). */
function daysUntil(iso: string | null): number | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (isNaN(d.getTime())) return null;
  return Math.ceil((d.getTime() - Date.now()) / 86_400_000);
}

/** Occhiello d'uscita per la card in evidenza. */
function releaseKicker(iso: string | null): string {
  const d = daysUntil(iso);
  if (d === null) return "IN USCITA";
  if (d <= 0) return "AL CINEMA DA OGGI";
  if (d === 1) return "ESCE DOMANI";
  return `ESCE TRA ${d} GIORNI`;
}

/** Poster con fallback automatico. */
function PosterImage({
  uri,
  style,
}: {
  uri: string | null;
  style?: object;
}) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [uri]);
  if (!uri || failed) {
    return (
      <View style={[styles.poster, styles.posterEmpty, style]}>
        <Text style={{ fontSize: 26 }}>🎬</Text>
      </View>
    );
  }
  return (
    <Image
      source={{ uri }}
      style={[styles.poster, style]}
      resizeMode="cover"
      onError={() => setFailed(true)}
    />
  );
}

const styles = StyleSheet.create({
  /* Header */
  header: {
    paddingHorizontal: 16,
    paddingTop: 14,
  },
  backBtn: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: "center",
    justifyContent: "center",
    ...Platform.select({
      ios: {},
      default: { backgroundColor: "rgba(255,255,255,0.10)" },
    }),
  },
  backText: {
    color: theme.colors.text,
    fontSize: 24,
    fontWeight: "700",
    marginTop: -2,
  },
  masthead: {
    paddingHorizontal: 16,
    paddingTop: 10,
    paddingBottom: 16,
  },
  eyebrow: {
    color: theme.colors.accent,
    fontSize: 10,
    fontWeight: "800",
    letterSpacing: 3,
    textTransform: "uppercase",
  },
  pageTitle: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 32,
    fontWeight: "700",
    letterSpacing: -0.5,
    marginTop: 4,
  },

  /* Card in evidenza */
  featured: {
    marginHorizontal: 16,
    borderRadius: theme.radius.lg,
    borderWidth: 1,
    borderColor: theme.colors.border,
    overflow: "hidden",
  },
  featuredGrad: {
    flexDirection: "row",
    padding: 14,
    gap: 14,
    alignItems: "stretch",
  },
  featuredPoster: {
    width: 112,
    aspectRatio: 2 / 3,
    borderRadius: theme.radius.sm,
  },
  featuredBody: { justifyContent: "center", gap: 6 },
  featuredKicker: {
    color: theme.colors.accent,
    fontSize: 10,
    fontWeight: "800",
    letterSpacing: 2,
  },
  featuredTitle: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 20,
    fontWeight: "700",
    lineHeight: 24,
  },
  featuredDate: {
    color: theme.colors.textDim,
    fontSize: 12,
    fontVariant: ["tabular-nums"],
  },
  featuredBook: {
    marginTop: 8,
    alignSelf: "flex-start",
    backgroundColor: theme.colors.accent,
    borderRadius: theme.radius.sm,
    paddingHorizontal: 14,
    paddingVertical: 9,
  },
  featuredBookText: {
    color: theme.colors.bg,
    fontSize: 13,
    fontWeight: "800",
  },

  /* Riga di contesto */
  statRow: {
    marginHorizontal: 16,
    marginTop: 16,
    marginBottom: 4,
    gap: 10,
  },
  statText: {
    color: theme.colors.text,
    fontSize: 11,
    fontWeight: "800",
    letterSpacing: 1.5,
    textTransform: "uppercase",
  },
  statRule: {
    width: 24,
    height: StyleSheet.hairlineWidth,
    backgroundColor: theme.colors.border,
  },
  statHint: { color: theme.colors.textDim, fontSize: 11, flexShrink: 1 },

  error: { color: theme.colors.warn, fontSize: 12, marginHorizontal: 16, marginTop: 8 },
  sectionHead: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    paddingHorizontal: 16,
    marginTop: 18,
    marginBottom: 12,
  },
  sectionLabel: {
    color: theme.colors.accent,
    fontSize: 11,
    fontWeight: "800",
    letterSpacing: 2.5,
  },
  sectionCount: {
    color: theme.colors.textDim,
    fontSize: 11,
    fontWeight: "700",
    fontVariant: ["tabular-nums"],
  },

  /* Griglia */
  gridRow: { flexDirection: "row", gap: 12, paddingHorizontal: 16, marginBottom: 12 },
  sectionRule: {
    flex: 1,
    height: StyleSheet.hairlineWidth,
    backgroundColor: theme.colors.border,
  },
  card: {
    flex: 1,
    backgroundColor: theme.colors.surface,
    borderWidth: 1,
    borderColor: theme.colors.border,
    borderRadius: theme.radius.md,
    padding: 10,
  },
  posterWrap: { position: "relative" },
  poster: {
    width: "100%",
    aspectRatio: 2 / 3,
    borderRadius: theme.radius.sm,
    backgroundColor: theme.colors.surfaceAlt,
  },
  posterEmpty: {
    alignItems: "center",
    justifyContent: "center",
  },
  soonBadge: {
    position: "absolute",
    top: 8,
    left: 8,
    backgroundColor: theme.colors.accent,
    borderRadius: 6,
    paddingHorizontal: 7,
    paddingVertical: 3,
  },
  soonBadgeText: {
    color: theme.colors.bg,
    fontSize: 9,
    fontWeight: "800",
    letterSpacing: 0.8,
  },
  cardTitle: {
    color: theme.colors.text,
    fontSize: 13,
    fontWeight: "700",
    lineHeight: 17,
    marginTop: 9,
  },
  cardDate: {
    color: theme.colors.textDim,
    fontSize: 10,
    marginTop: 2,
    marginBottom: 10,
    fontVariant: ["tabular-nums"],
  },
  cardBook: {
    borderWidth: 1,
    borderColor: theme.colors.accent + "66",
    backgroundColor: theme.colors.accent + "14",
    borderRadius: theme.radius.xs,
    paddingVertical: 7,
    alignItems: "center",
  },
  cardBookText: {
    color: theme.colors.accent,
    fontSize: 10,
    fontWeight: "800",
    letterSpacing: 1.5,
  },
});
