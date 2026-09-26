import React, {
  memo,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  FlatList,
  Image,
  Platform,
  Pressable,
  RefreshControl,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { GlassView } from "expo-glass-effect";
import { Animated, Easing } from "react-native";
import { EASE_COUTURE, SPRING, ShimmerText, useCountUp } from "../../src/motion";
import { useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { theme, fonts } from "../../src/theme";
import { styles as s } from "../../src/theme";
import { useStoreContext } from "../../src/storage/StoreContext";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { activeSources, loadNewsCache } from "../../src/storage/store";
import { timeAgo } from "../../src/logic/news";
import {
  refreshNews,
  notifyNewItems,
  registerBackgroundFetch,
} from "../../src/logic/liveNews";
import { isPreSale, isUpcoming } from "../../src/logic/alerts";
import { NewsItem } from "../../src/models/types";
import {
  AiArticle,
  ensureAiArticles,
} from "../../src/logic/aiNews";
import { Badge, EmptyState, TextInput } from "../../src/components/ui";
import { ScreenHeader } from "../../src/components/ScreenHeader";
import { SkeletonRow } from "../../src/components/Skeletons";

const DATA_OGGI = new Intl.DateTimeFormat("it-IT", {
  weekday: "long",
  day: "numeric",
  month: "long",
});

const READ_KEY = "cineflash/read-history/v1";

export default function NewsScreen() {
  const { settings, savedNews } = useStoreContext();
  const insets = useSafeAreaInsets();
  const [items, setItems] = useState<NewsItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sourceFilter, setSourceFilter] = useState<string | "all">("all");
  const [aiOnly, setAiOnly] = useState(false);
  const [query, setQuery] = useState("");
  const [newIds, setNewIds] = useState<string[]>([]);
  const [newCount, setNewCount] = useState(0);
  /* Articoli riscritti dall'AI: id → articolo. La lista si aggiorna
  progressivamente man mano che la redazione AI consegna. */
  const [aiArticles, setAiArticles] = useState<Record<string, AiArticle>>({});
  const aiArticlesRef = useRef<Record<string, AiArticle>>({});
  const newIdsRef = useRef<Set<string>>(new Set());
  const mountedRef = useRef(false);
  const listRef = useRef<FlatList<NewsItem>>(null);

  const toggleSaved = savedNews.toggle;

  const sources = useMemo(() => activeSources(settings), [settings]);

  /* Motore di animazione: ingresso pill a molla + shimmer dorato */
  const pillAnim = useRef(new Animated.Value(0)).current;
  const pillShown = useRef(false);
  useEffect(() => {
    if (newCount > 0 && !pillShown.current) {
      pillShown.current = true;
      Animated.spring(pillAnim, { toValue: 1, ...SPRING.gentle, useNativeDriver: true }).start();
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    }
    if (newCount === 0) {
      // reset silenzioso per il prossimo lotto di notizie
      pillShown.current = false;
      pillAnim.setValue(0);
    }
  }, [newCount, pillAnim]);
  const pillStyle = {
    opacity: pillAnim,
    transform: [
      {
        scale: pillAnim.interpolate({ inputRange: [0, 1], outputRange: [0.4, 1] }),
      },
    ],
  };
  const shownCount = useCountUp(newCount, 600);
  const sourceNames = useMemo(
    () => [...new Set(items.map((x) => x.source))],
    [items]
  );

  // Set O(1) per lookup nelle righe (evita .includes/.some per ogni render)
  const newIdSet = useMemo(() => new Set(newIds), [newIds]);
  const savedIdSet = useMemo(
    () => new Set(savedNews.saved.map((x) => x.id)),
    [savedNews.saved]
  );

  const applyNewIds = useCallback((ids: string[]) => {
    newIdsRef.current = new Set([...newIdsRef.current, ...ids]);
    setNewIds([...newIdsRef.current]);
  }, []);

  /** Aggiorna via refreshNews (cache + rete) e segnala i nuovi articoli. */
  const runRefresh = useCallback(
    async (silent = false) => {
      if (!silent) setRefreshing(true);
      setError(null);
      try {
        const res = await refreshNews();
        const cached = await loadNewsCache();
        if (cached?.items?.length) {
          // Aggiorna lo state solo se qualcosa è davvero cambiato:
          // evita il re-render completo della lista a ogni poll.
          setItems((prev) => {
            if (
              prev.length === cached.items.length &&
              prev.every(
                (x, i) =>
                  x.id === cached.items[i].id &&
                  x.publishedAt === cached.items[i].publishedAt
              )
            ) {
              return prev;
            }
            return cached.items;
          });
        }
        if (res.newCount > 0) {
          applyNewIds(res.fresh.map((x) => x.id));
          setNewCount((c) => c + res.newCount);
          if (silent) await notifyNewItems(res);
        }
        if (res.failed.length > 0 && (cached?.items?.length ?? 0) === 0) {
          setError(`Nessun feed raggiungibile (${res.failed.join(", ")}).`);
        } else if (res.failed.length > 0) {
          setError(`Alcune fonti non rispondono: ${res.failed.join(", ")}.`);
        }
      } catch {
        setError("Connessione non riuscita. Riprova più tardi.");
      } finally {
        setLoading(false);
        setRefreshing(false);
      }
    },
    [applyNewIds]
  );

  // Primo caricamento (cache prima, rete dopo) + refresh quando cambiano le fonti
  const sourcesKey = sources.map((x) => x.key).join(",");
  useEffect(() => {
    if (!mountedRef.current) {
      mountedRef.current = true;
      (async () => {
        const cached = await loadNewsCache();
        if (cached?.items?.length) {
          setItems(cached.items);
          setLoading(false);
        }
        await runRefresh(true);
        registerBackgroundFetch();
      })();
    } else {
      runRefresh(true);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sourcesKey]);

  /* Redazione AI: riscrive le notizie più recenti in articoli chiari.
  Ogni articolo pronto aggiorna la riga corrispondente senza attendere la coda. */
  useEffect(() => {
    if (items.length === 0) return;
    let alive = true;
    ensureAiArticles(items, (art) => {
      if (!alive) return;
      setAiArticles((prev) => ({ ...prev, [art.id]: art }));
    }).catch(() => {});
    return () => {
      alive = false;
    };
  }, [items]);

  // Polling automatico: le notizie compaiono da sole, senza pull-to-refresh
  useEffect(() => {
    const t = setInterval(() => runRefresh(true), 60_000);
    return () => clearInterval(t);
  }, [runRefresh]);

  const showNew = () => {
    Haptics.selectionAsync();
    listRef.current?.scrollToOffset({ offset: 0, animated: true });
    setNewCount(0);
    newIdsRef.current = new Set();
    setNewIds([]);
  };

  /* ---------- Contatori per le due pagine dedicate ---------- */

  const savedCount = savedNews.saved.length;
  const presaleCount = useMemo(() => items.filter(isPreSale).length, [items]);
  const upcomingCount = useMemo(
    () => items.filter((x) => !isPreSale(x) && isUpcoming(x)).length,
    [items]
  );

  const visible = useMemo(() => {
    let list = items;
    if (sourceFilter !== "all") list = list.filter((x) => x.source === sourceFilter);
    if (aiOnly) list = list.filter((x) => aiArticles[x.id] != null);
    const q = query.trim().toLowerCase();
    if (q.length >= 2) {
      list = list.filter(
        (x) => x.title.toLowerCase().includes(q) || x.summary.toLowerCase().includes(q)
      );
    }
    return list;
  }, [items, sourceFilter, query, aiOnly, aiArticles]);

  /* Storia di lettura: gli articoli aperti vengono attenuati in lista.
  Persistita in AsyncStorage, limitata alle ultime 300 voci. */
  const [readIds, setReadIds] = useState<string[]>([]);
  const readIdSet = useMemo(() => new Set(readIds), [readIds]);
  useEffect(() => {
    AsyncStorage.getItem(READ_KEY)
      .then((raw) => {
        if (raw) setReadIds(JSON.parse(raw) as string[]);
      })
      .catch(() => {});
  }, []);
  const markRead = useCallback((id: string) => {
    setReadIds((prev) => {
      if (prev.includes(id)) return prev;
      const next = [id, ...prev].slice(0, 300);
      AsyncStorage.setItem(READ_KEY, JSON.stringify(next)).catch(() => {});
      return next;
    });
  }, []);

  const router = useRouter();

  const open = useCallback(
    (item: NewsItem) => {
      Haptics.selectionAsync();
      markRead(item.id);
      router.push({
        pathname: "/article",
        params: { url: item.link, title: item.title, source: item.source },
      });
    },
    [router, markRead]
  );

  /** AI: spiega subito la notizia senza aprire l'articolo. */
  const explainWithAI = useCallback(
    (item: NewsItem) => {
      Haptics.selectionAsync();
      router.push({
        pathname: "/ai",
        params: {
          mode: "news",
          title: item.title,
          source: item.source,
          text: item.summary ? `${item.title}. ${item.summary}` : item.title,
        },
      });
    },
    [router]
  );

  const toggleSave = useCallback(
    (item: NewsItem) => {
      toggleSaved(item);
    },
    [toggleSaved]
  );

  const share = useCallback(async (item: NewsItem) => {
    Haptics.selectionAsync();
    try {
      await Share.share({ message: `${item.title}\n${item.link}` });
    } catch {}
  }, []);

  const renderItem = useCallback(
    ({ item }: { item: NewsItem }) => (
      <NewsRow
        item={item}
        ai={aiArticles[item.id] ?? null}
        isNew={newIdSet.has(item.id)}
        saved={savedIdSet.has(item.id)}
        read={readIdSet.has(item.id)}
        onOpen={open}
        onExplain={explainWithAI}
        onToggleSave={toggleSave}
        onShare={share}
      />
    ),
    [aiArticles, newIdSet, savedIdSet, readIdSet, open, explainWithAI, toggleSave, share]
  );

  const keyExtractor = useCallback((x: NewsItem) => x.id, []);

  return (
    <View style={s.screen}>
      <FlatList
        ref={listRef}
        data={visible}
        keyExtractor={keyExtractor}
        renderItem={renderItem}
        /* Virtualizzazione aggressiva: poche righe montate = lista leggera */
        initialNumToRender={8}
        maxToRenderPerBatch={6}
        windowSize={7}
        updateCellsBatchingPeriod={50}
        contentContainerStyle={{ paddingBottom: 24 + insets.bottom }}
        ListHeaderComponent={
          <View style={[styles.header, { paddingTop: 12 + insets.top }]}>
            {/* Masthead condiviso: occhiello con data, titolo serif, salvati + pill */}
            <ScreenHeader
              eyebrow={`CineFlash · ${DATA_OGGI.format(new Date())}`}
              title="Notizie"
              right={
                <View style={s.row}>
                  {newCount > 0 && (
                    <Pressable onPress={showNew}>
                      <Animated.View style={pillStyle}>
                        <GlassView
                          glassEffectStyle="regular"
                          tintColor={theme.colors.accent}
                          isInteractive
                          style={styles.pillGlass}
                        >
                          <ShimmerText text={`${shownCount} nuove`} style={styles.newPillText} />
                        </GlassView>
                      </Animated.View>
                    </Pressable>
                  )}
                  <Pressable
                    onPress={() => {
                      Haptics.selectionAsync();
                      router.push("/saved");
                    }}
                    hitSlop={8}
                  >
                    <View style={styles.savedBtn}>
                      <Text style={styles.savedBtnText}>🔖</Text>
                      {savedCount > 0 ? <View style={styles.savedDot} /> : null}
                    </View>
                  </Pressable>
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
                </View>
              }
            />

            {/* Ricerca */}
            <View style={{ marginTop: 10 }}>
              <View style={s.row}>
                <View style={s.grow}>
                  <TextInput
                    value={query}
                    onChangeText={setQuery}
                    placeholder="Cerca…"
                    autoCapitalize="sentences"
                  />
                </View>
                {query.trim().length > 0 ? (
                  <Pressable
                    onPress={() => {
                      Haptics.selectionAsync();
                      setQuery("");
                    }}
                    hitSlop={8}
                    style={styles.clearBtn}
                  >
                    <Text style={styles.clearBtnText}>✕</Text>
                  </Pressable>
                ) : null}
              </View>
            </View>

            {/* Due entrate compatte: prevendite e film in arrivo */}
            <View style={[s.row, { marginTop: 10, gap: 10 }]}>
              <EntryCard
                icon="🎟️"
                label="Prevendite"
                count={presaleCount}
                onPress={() => {
                  Haptics.selectionAsync();
                  router.push("/presale");
                }}
              />
              <EntryCard
                icon="📅"
                label="In arrivo"
                count={upcomingCount}
                onPress={() => {
                  Haptics.selectionAsync();
                  router.push("/upcoming");
                }}
              />
            </View>

            {/* Filtri fonte: una riga scrollabile, niente wrap */}
            <ScrollView
              horizontal
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={[styles.chipRow, { marginTop: 10 }]}
            >
              <FilterChip
                label="Tutte"
                active={sourceFilter === "all"}
                onPress={() => setSourceFilter("all")}
              />
              {sourceNames.map((name) => (
                <FilterChip
                  key={name}
                  label={name}
                  active={sourceFilter === name}
                  onPress={() => setSourceFilter(name)}
                />
              ))}
              <FilterChip
                label="✨ Solo AI"
                active={aiOnly}
                onPress={() => setAiOnly((v) => !v)}
              />
            </ScrollView>

            {error ? <Text style={styles.error}>{error}</Text> : null}
          </View>
        }
        ListEmptyComponent={
          loading ? (
            <View>
              {[0, 1, 2, 3, 4, 5].map((i) => (
                <SkeletonRow key={i} height={52} />
              ))}
            </View>
          ) : query.trim().length >= 2 ? (
            <EmptyState icon="🔍" title="Nessun risultato" subtitle="Prova con parole diverse." />
          ) : sourceFilter !== "all" ? (
            <EmptyState
              icon="📰"
              title={`Niente da ${sourceFilter}`}
              subtitle="Questa testata non ha notizie in cache: prova “Tutte” o un'altra fonte."
            />
          ) : (
            <EmptyState
              icon="🍿"
              title="Nessuna notizia"
              subtitle="Controlla la connessione o abilita altre fonti."
            />
          )
        }
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => runRefresh(false)}
            tintColor={theme.colors.accent}
          />
        }
      />
    </View>
  );
}

/* ---------- Riga memoizzata: si ridisegna solo se le sue props cambiano ---------- */

type RowProps = {
  item: NewsItem;
  /** Articolo riscritto dall'AI, se già pronto. */
  ai: AiArticle | null;
  isNew: boolean;
  saved: boolean;
  /** Già letto: riga attenuata. */
  read: boolean;
  onOpen: (item: NewsItem) => void;
  onExplain: (item: NewsItem) => void;
  onToggleSave: (item: NewsItem) => void;
  /** Pressione lunga: condivisione rapida. */
  onShare: (item: NewsItem) => void;
};

const NewsRow = memo(function NewsRow({
  item,
  ai,
  isNew,
  saved,
  read,
  onOpen,
  onExplain,
  onToggleSave,
  onShare,
}: RowProps) {
  const img = item.imageUrl ?? ai?.images?.[0] ?? null;
  return (
    <Pressable
      onPress={() => onOpen(item)}
      onLongPress={() => onShare(item)}
      delayLongPress={380}
      style={({ pressed }) => [styles.rowCard, pressed && { opacity: 0.75 }]}
    >
      {img ? (
        <RowImage uri={img} />
      ) : (
        <View style={[styles.rowThumb, styles.rowThumbEmpty]}>
          <Text style={{ fontSize: 17 }}>🎬</Text>
        </View>
      )}
      <View style={[styles.rowBody, { flex: 1 }]}>
        <View style={s.row}>
          {ai ? <Badge label="AI" tone="accent" /> : null}
          {isNew ? <Badge label="NUOVO" tone="warn" /> : null}
          <Text style={styles.source} numberOfLines={1}>
            {item.source.toUpperCase()}
          </Text>
          <View style={s.grow} />
          <Text style={styles.time}>{timeAgo(item.publishedAt)}</Text>
        </View>
        <Text style={[styles.rowTitle, read && styles.rowTitleRead]} numberOfLines={2}>
          {ai?.title ?? item.title}
        </Text>
        {saved ? <Text style={styles.savedMark}>salvato</Text> : null}
      </View>
      <Pressable onPress={() => onExplain(item)} hitSlop={8} style={styles.miniAction}>
        <View style={styles.miniBtn}>
          <Text style={styles.aiActionText}>✨</Text>
        </View>
      </Pressable>
      <Pressable onPress={() => onToggleSave(item)} hitSlop={8} style={styles.miniAction}>
        <View style={styles.miniBtn}>
          <Text style={styles.miniActionText}>{saved ? "✓" : "＋"}</Text>
        </View>
      </Pressable>
    </Pressable>
  );
});

/** Piccola porta verso una pagina dedicata: icona, nome e conteggio animato. */
function EntryCard({
  icon,
  label,
  count,
  onPress,
}: {
  icon: string;
  label: string;
  count: number;
  onPress: () => void;
}) {
  const shown = useCountUp(count as number, 800);
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [styles.entryCard, pressed && { opacity: 0.7 }]}
    >
      <Text style={styles.entryIcon}>{icon}</Text>
      <View style={s.grow}>
        <Text style={styles.entryLabel}>{label}</Text>
        <Text style={styles.entryCount}>{shown > 0 ? shown : "—"}</Text>
  </View>
      <Text style={styles.entryChevron}>›</Text>
    </Pressable>
  );
}

/** Thumbnail delle righe con fallback automatico. */
const RowImage = memo(function RowImage({ uri }: { uri: string }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    setFailed(false);
  }, [uri]);
  if (failed) {
    return (
      <View style={[styles.rowThumb, styles.rowThumbEmpty]}>
        <Text style={{ fontSize: 17 }}>🎬</Text>
      </View>
    );
  }
  return (
    <Image
      source={{ uri }}
      style={styles.rowThumb}
      resizeMode="cover"
      onError={() => setFailed(true)}
    />
  );
});

function FilterChip({
  label,
  active,
  onPress,
}: {
  label: string;
  active: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={() => {
        Haptics.selectionAsync();
        onPress();
      }}
    >
      <View style={[styles.chip, active && styles.chipOn]}>
        <Text style={[styles.chipText, active && styles.chipTextOn]}>{label}</Text>
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 8,
  },
  masthead: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 28,
    fontWeight: "700",
    letterSpacing: -0.5,
    lineHeight: 33,
  },
  mastheadDate: {
    color: theme.colors.textDim,
    fontSize: 11,
    fontWeight: "600",
    marginLeft: 10,
    textTransform: "capitalize",
  },
  savedBtn: {
    width: 30,
    height: 30,
    borderRadius: 15,
    alignItems: "center",
    justifyContent: "center",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    backgroundColor: theme.colors.surfaceAlt,
  },
  gearBtn: {
    width: 30,
    height: 30,
    borderRadius: 15,
    alignItems: "center",
    justifyContent: "center",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    backgroundColor: theme.colors.surfaceAlt,
    marginLeft: 8,
  },
  gearIcon: {
    fontSize: 13,
    color: theme.colors.textDim,
  },
  savedBtnText: { fontSize: 12 },
  clearBtn: {
    width: 34,
    height: 34,
    borderRadius: 17,
    marginLeft: 8,
    alignItems: "center",
    justifyContent: "center",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    backgroundColor: theme.colors.surfaceAlt,
  },
  clearBtnText: { color: theme.colors.textDim, fontSize: 13, fontWeight: "700" },
  savedDot: {
    position: "absolute",
    top: -1,
    right: -1,
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: theme.colors.accent,
    borderWidth: 1,
    borderColor: theme.colors.surface,
  },
  pillGlass: {
    borderRadius: 999,
    ...Platform.select({
      ios: {},
      default: { backgroundColor: theme.colors.accent },
    }),
  },
  newPillText: {
    color: theme.colors.onAccent,
    fontSize: 12,
    fontWeight: "700",
    paddingVertical: 6,
    paddingHorizontal: 12,
  },
  error: { color: theme.colors.warn, fontSize: 12, marginTop: 8, lineHeight: 17 },

  /* Entrate compatte */
  entryCard: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: theme.colors.surface,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    borderRadius: theme.radius.md,
    paddingHorizontal: 12,
    paddingVertical: 9,
    gap: 9,
  },
  entryIcon: { fontSize: 18 },
  entryLabel: {
    color: theme.colors.textDim,
    fontSize: 10,
    fontWeight: "700",
    letterSpacing: 0.5,
    textTransform: "uppercase",
  },
  entryCount: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 18,
    fontWeight: "700",
    marginTop: 1,
    fontVariant: ["tabular-nums"],
  },
  entryChevron: {
    color: theme.colors.textDim,
    fontSize: 18,
    fontWeight: "300",
  },

  /* Filtri: una riga orizzontale */
  chipRow: {
    paddingRight: 16,
    gap: 6,
  },
  chip: {
    paddingHorizontal: 11,
    paddingVertical: 5,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    backgroundColor: theme.colors.surfaceAlt,
  },
  chipOn: { backgroundColor: theme.colors.text, borderColor: theme.colors.text },
  chipText: {
    color: theme.colors.textDim,
    fontSize: 12,
    fontWeight: "600",
  },
  chipTextOn: { color: theme.colors.onAccent, fontWeight: "700" },

  /* Righe compatte */
  rowCard: {
    flexDirection: "row",
    alignItems: "center",
    marginHorizontal: 16,
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: theme.colors.border,
  },
  rowThumb: { width: 72, height: 52, borderRadius: theme.radius.xs },
  rowThumbEmpty: {
    backgroundColor: theme.colors.surfaceAlt,
    alignItems: "center",
    justifyContent: "center",
  },
  rowBody: { marginLeft: 11 },
  source: {
    color: theme.colors.accent,
    fontSize: 10,
    fontWeight: "800",
    letterSpacing: 0.8,
    marginLeft: 6,
    flexShrink: 1,
  },
  rowTitle: {
    color: theme.colors.text,
    fontSize: 15,
    fontWeight: "600",
    lineHeight: 20,
    marginTop: 3,
  },
  rowTitleRead: { color: theme.colors.textDim, fontWeight: "500" },
  savedMark: { color: theme.colors.ok, fontSize: 10, fontWeight: "700", marginTop: 2 },
  miniAction: {
    width: 30,
    height: 30,
    marginLeft: 8,
    marginRight: 4,
  },
  /* Bottone leggero: niente Liquid Glass per riga (centinaia di layer uccidono la lista) */
  miniBtn: {
    width: 30,
    height: 30,
    borderRadius: 15,
    alignItems: "center",
    justifyContent: "center",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    backgroundColor: theme.colors.surfaceAlt,
  },
  miniActionText: { color: theme.colors.textDim, fontSize: 15, fontWeight: "600" },
  aiActionText: { fontSize: 12 },
  time: { color: theme.colors.textDim, fontSize: 11 },
});
