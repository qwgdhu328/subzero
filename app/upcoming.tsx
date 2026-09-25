import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  FlatList,
  Image,
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
import { loadNewsCache } from "../src/storage/store";
import { refreshNews } from "../src/logic/liveNews";
import { isPreSale, isUpcoming } from "../src/logic/alerts";
import { timeAgo } from "../src/logic/news";
import { findMovieFromNewsTitle } from "../src/logic/itunes";
import { NewsItem } from "../src/models/types";
import { EmptyState, Spinner } from "../src/components/ui";
import { DetailMovie, MovieDetailSheet } from "../src/components/MovieDetailSheet";

/**
 * Pagina "Film in arrivo": uscite, annunci e trailer dei film che arrivano
 * al cinema. Tap → pagina del film; pressione lunga → articolo originale.
 */
export default function UpcomingScreen() {
  const router = useRouter();
  const { title } = useLocalSearchParams<{ title?: string }>();
  const { watchlist, settings } = useStoreContext();
  const insets = useSafeAreaInsets();

  const [items, setItems] = useState<NewsItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [searching, setSearching] = useState(false);
  const [detail, setDetail] = useState<DetailMovie | null>(null);
  const mountedRef = useRef(false);

  const load = useCallback(async (silent: boolean) => {
    if (!silent) setRefreshing(true);
    try {
      await refreshNews();
      const cached = await loadNewsCache();
      const all = cached?.items ?? [];
      setItems(all.filter((x) => !isPreSale(x) && isUpcoming(x)));
    } catch {
      // con cache vuota resta la lista caricata prima; la UI non si rompe
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    if (mountedRef.current) return;
    mountedRef.current = true;
    (async () => {
      const cached = await loadNewsCache();
      if (cached?.items?.length) {
        setItems(cached.items.filter((x) => !isPreSale(x) && isUpcoming(x)));
        setLoading(false);
      }
      await load(true);
    })();
  }, [load]);

  /** Articolo originale (dalla pressione lunga). */
  const openArticle = (item: NewsItem) => {
    router.push({
      pathname: "/article",
      params: { url: item.link, title: item.title, source: item.source },
    });
  };

  /** Cerca il film citato dalla notizia e apre la sua pagina. */
  const openMovie = async (item: NewsItem) => {
    Haptics.selectionAsync();
    setSearching(true);
    try {
      const movie = await findMovieFromNewsTitle(item.title);
      setSearching(false);
      if (movie) {
        setDetail({
          ...movie,
          needsTmdb: true,
          articleUrl: item.link,
          articleSource: item.source,
        });
      } else {
        // Nessun film riconosciuto: si torna all'articolo della fonte
        openArticle(item);
      }
    } catch {
      setSearching(false);
      openArticle(item);
    }
  };

  /** Apre la pagina AI con i dati del film come contesto. */
  const explainMovieWithAI = (m: DetailMovie) => {
    const parts = [
      m.overview ? `Trama: ${m.overview}` : "",
      m.genres?.length ? `Generi: ${m.genres.join(", ")}.` : "",
      m.releaseDate ? `Uscita: ${m.releaseDate}.` : "",
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
  };

  const renderItem = ({ item }: { item: NewsItem }) => (
    <Pressable
      onPress={() => openMovie(item)}
      onLongPress={() => openArticle(item)}
      delayLongPress={350}
      style={({ pressed }) => [styles.row, pressed && { opacity: 0.75 }]}
    >
      {item.imageUrl ? (
        <RowImage uri={item.imageUrl} />
      ) : (
        <View style={[styles.thumb, styles.thumbEmpty]}>
          <Text style={{ fontSize: 22 }}>📅</Text>
        </View>
      )}
      <View style={styles.rowBody}>
        <View style={s.row}>
          <Text style={styles.source} numberOfLines={1}>
            {item.source.toUpperCase()}
          </Text>
          <Text style={styles.dot}>·</Text>
          <Text style={styles.time}>{timeAgo(item.publishedAt)}</Text>
        </View>
        <Text style={styles.rowTitle} numberOfLines={2}>
          {item.title}
        </Text>
        {item.summary ? (
          <Text style={styles.rowSummary} numberOfLines={2}>
            {item.summary}
          </Text>
        ) : null}
      </View>
      <Text style={styles.chevron}>›</Text>
    </Pressable>
  );

  return (
    <View style={s.screen}>
      <Stack.Screen options={{ headerShown: false }} />
      <FlatList
        data={items}
        keyExtractor={(x) => x.id}
        renderItem={renderItem}
        contentContainerStyle={{ paddingBottom: 40 + insets.bottom }}
        ListHeaderComponent={
          <View>
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
            {/* Masthead editoriale: occhiello + titolo serif */}
            <View style={styles.mastheadWrap}>
              <Text style={s.eyebrow}>CineFlash · Prossimamente</Text>
              <Text style={[styles.pageTitle, { fontFamily: fonts.serif }]} numberOfLines={1}>
                {title && title.length > 0 ? title : "Film in arrivo"}
              </Text>
            </View>

            {/* Hero con il conteggio */}
            <LinearGradient
              colors={[theme.colors.surfaceRaised, theme.colors.surface]}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
              style={styles.hero}
            >
              <Text style={styles.heroIcon}>📅</Text>
              <View style={s.grow}>
                <Text style={styles.heroCount}>
                  {items.length > 0 ? items.length : "—"}
                </Text>
                <Text style={styles.heroLabel}>
                  {items.length === 1
                    ? "titolo annunciato o in uscita"
                    : "titoli annunciati o in uscita"}
                </Text>
              </View>
            </LinearGradient>

            <Text style={styles.hint}>
              Tocca una notizia per aprire la pagina del film. Tieni premuto
              per leggere l'articolo originale.
            </Text>
          </View>
        }
        ListEmptyComponent={
          loading ? (
            <Spinner label="Carico i film in arrivo…" />
          ) : (
            <EmptyState
              icon="📅"
              title="Nessun annuncio"
              subtitle="Quando arrivano nuove uscite al cinema, le trovi qui."
            />
          )
        }
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => load(false)}
            tintColor={theme.colors.accent}
          />
        }
      />

      {/* Indicatore ricerca film in corso */}
      {searching && (
        <View style={styles.searchingToast}>
          <Text style={styles.searchingText}>🎬 Cerco la pagina del film…</Text>
        </View>
      )}

      {/* Dettaglio film */}
      <MovieDetailSheet
        movie={detail}
        onClose={() => setDetail(null)}
        onOpenAI={explainMovieWithAI}
        watchlist={watchlist}
        aiDisabled={settings.aiDisabled}
      />
    </View>
  );
}

/** Thumbnail con fallback automatico se l'immagine non carica. */
function RowImage({ uri }: { uri: string }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [uri]);
  if (failed) {
    return (
      <View style={[styles.thumb, styles.thumbEmpty]}>
        <Text style={{ fontSize: 22 }}>📅</Text>
      </View>
    );
  }
  return (
    <Image
      source={{ uri }}
      style={styles.thumb}
      resizeMode="cover"
      onError={() => setFailed(true)}
    />
  );
}

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: 16,
    paddingTop: 14,
    paddingBottom: 12,
    gap: 12,
  },
  mastheadWrap: {
    paddingHorizontal: 16,
    paddingTop: 6,
    paddingBottom: 12,
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
  pageTitle: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 30,
    fontWeight: "700",
    letterSpacing: -0.5,
    lineHeight: 36,
    marginTop: 4,
  },
  hero: {
    flexDirection: "row",
    alignItems: "center",
    marginHorizontal: 16,
    marginBottom: 8,
    paddingHorizontal: 18,
    paddingVertical: 16,
    borderRadius: theme.radius.lg,
    borderWidth: 1,
    borderColor: theme.colors.border,
    gap: 12,
  },
  heroIcon: { fontSize: 30 },
  heroCount: {
    color: theme.colors.text,
    fontSize: 30,
    fontWeight: "900",
    letterSpacing: -0.5,
    fontVariant: ["tabular-nums"],
    lineHeight: 34,
  },
  heroLabel: {
    color: theme.colors.textDim,
    fontSize: 12,
    fontWeight: "600",
  },
  hint: {
    color: theme.colors.textDim,
    fontSize: 11,
    marginHorizontal: 16,
    marginBottom: 4,
  },
  row: {
    flexDirection: "row",
    alignItems: "center",
    marginHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: theme.colors.border,
    gap: 12,
  },
  thumb: {
    width: 92,
    height: 64,
    borderRadius: theme.radius.sm,
    backgroundColor: theme.colors.surfaceAlt,
  },
  thumbEmpty: {
    alignItems: "center",
    justifyContent: "center",
  },
  rowBody: { flex: 1 },
  source: {
    color: theme.colors.accent,
    fontSize: 10,
    fontWeight: "800",
    letterSpacing: 0.8,
    flexShrink: 1,
  },
  dot: { color: theme.colors.textDim, fontSize: 10, marginHorizontal: 5 },
  time: { color: theme.colors.textDim, fontSize: 11 },
  rowTitle: {
    color: theme.colors.text,
    fontSize: 16,
    fontWeight: "700",
    lineHeight: 21,
    marginTop: 3,
  },
  rowSummary: {
    color: theme.colors.textDim,
    fontSize: 13,
    lineHeight: 18,
    marginTop: 4,
  },
  chevron: {
    color: theme.colors.textDim,
    fontSize: 22,
    fontWeight: "300",
  },
  searchingToast: {
    position: "absolute",
    bottom: 32,
    alignSelf: "center",
    backgroundColor: theme.colors.surfaceRaised,
    borderWidth: 1,
    borderColor: theme.colors.border,
    borderRadius: 999,
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  searchingText: { color: theme.colors.text, fontSize: 13, fontWeight: "600" },
});
