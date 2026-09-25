import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  FlatList,
  Image,
  Platform,
  Pressable,
  RefreshControl,
  Share,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { GlassView } from "expo-glass-effect";
import { useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { theme, fonts } from "../../src/theme";
import { styles as s } from "../../src/theme";
import { useStoreContext } from "../../src/storage/StoreContext";
import { activeSources, loadNewsCache } from "../../src/storage/store";
import { timeAgo } from "../../src/logic/news";
import {
  refreshNews,
  notifyNewItems,
  registerBackgroundFetch,
} from "../../src/logic/liveNews";
import { isPreSale, isUpcoming } from "../../src/logic/alerts";
import { NewsItem } from "../../src/models/types";
import { Badge, EmptyState, Spinner, TextInput } from "../../src/components/ui";
import { AIBanner } from "../../src/components/AIBanner";

const DATA_OGGI = new Intl.DateTimeFormat("it-IT", {
  weekday: "long",
  day: "numeric",
  month: "long",
});

export default function NewsScreen() {
  const { settings, savedNews } = useStoreContext();
  const insets = useSafeAreaInsets();
  const [items, setItems] = useState<NewsItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sourceFilter, setSourceFilter] = useState<string | "all">("all");
  const [query, setQuery] = useState("");
  const [newIds, setNewIds] = useState<string[]>([]);
  const [newCount, setNewCount] = useState(0);
  const newIdsRef = useRef<Set<string>>(new Set());
  const mountedRef = useRef(false);
  const listRef = useRef<FlatList<NewsItem>>(null);

  const sources = useMemo(() => activeSources(settings), [settings]);
  const sourceNames = useMemo(
    () => [...new Set(items.map((x) => x.source))],
    [items]
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
        if (cached?.items?.length) setItems(cached.items);
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

  const presaleCount = useMemo(() => items.filter(isPreSale).length, [items]);
  const upcomingCount = useMemo(
    () => items.filter((x) => !isPreSale(x) && isUpcoming(x)).length,
    [items]
  );

  const visible = useMemo(() => {
    let list = items;
    if (sourceFilter !== "all") list = list.filter((x) => x.source === sourceFilter);
    const q = query.trim().toLowerCase();
    if (q.length >= 2) {
      list = list.filter(
        (x) => x.title.toLowerCase().includes(q) || x.summary.toLowerCase().includes(q)
      );
    }
    return list;
  }, [items, sourceFilter, query]);

  const router = useRouter();
  const open = (item: NewsItem) => {
    Haptics.selectionAsync();
    router.push({
      pathname: "/article",
      params: { url: item.link, title: item.title, source: item.source },
    });
  };

  /** AI: spiega subito la notizia senza aprire l'articolo. */
  const explainWithAI = (item: NewsItem) => {
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
  };

  const share = async (item: NewsItem) => {
    Haptics.selectionAsync();
    try {
      await Share.share({ message: `${item.title}\n${item.link}` });
    } catch {}
  };

  const toggleSave = (item: NewsItem) => {
    savedNews.toggle(item);
  };

  const renderItem = ({ item }: { item: NewsItem }) => (
    <Pressable
      onPress={() => open(item)}
      style={({ pressed }) => [styles.rowCard, pressed && { opacity: 0.75 }]}
    >
      {item.imageUrl ? (
        <RowImage uri={item.imageUrl} />
      ) : (
        <View style={[styles.rowThumb, styles.rowThumbEmpty]}>
          <Text style={{ fontSize: 18 }}>🎬</Text>
        </View>
      )}
      <View style={[styles.rowBody, { flex: 1 }]}>
        <View style={s.row}>
          {newIds.includes(item.id) ? <Badge label="NUOVO" tone="warn" /> : null}
          <Text style={styles.source} numberOfLines={1}>
            {item.source.toUpperCase()}
          </Text>
          <View style={s.grow} />
          <Text style={styles.time}>{timeAgo(item.publishedAt)}</Text>
        </View>
        <Text style={styles.rowTitle} numberOfLines={2}>
          {item.title}
        </Text>
        {savedNews.isSaved(item.id) ? <Text style={styles.savedMark}>salvato</Text> : null}
      </View>
      {!settings.aiDisabled && (
        <Pressable onPress={() => explainWithAI(item)} hitSlop={8} style={styles.miniAction}>
          <GlassView glassEffectStyle="clear" isInteractive style={styles.miniGlass}>
            <Text style={styles.aiActionText}>✨</Text>
          </GlassView>
        </Pressable>
      )}
      <Pressable onPress={() => toggleSave(item)} hitSlop={8} style={styles.miniAction}>
        <GlassView glassEffectStyle="clear" isInteractive style={styles.miniGlass}>
          <Text style={styles.miniActionText}>{savedNews.isSaved(item.id) ? "✓" : "＋"}</Text>
        </GlassView>
      </Pressable>
    </Pressable>
  );

  return (
    <View style={s.screen}>
      <FlatList
        ref={listRef}
        data={visible}
        keyExtractor={(x) => x.id}
        renderItem={renderItem}
        contentContainerStyle={{ paddingBottom: 32 + insets.bottom }}
        ListHeaderComponent={
          <View style={[styles.header, { paddingTop: 16 + insets.top }]}>
            {/* Masthead editoriale: occhiello, titolo serif e data di oggi */}
            <View style={s.row}>
              <Text style={s.eyebrow}>CineFlash</Text>
              <View style={[s.hairline, { marginLeft: 10 }]} />
              <Text style={styles.mastheadDate}>{DATA_OGGI.format(new Date())}</Text>
            </View>
            <View style={[s.row, { marginTop: 6, alignItems: "flex-end" }]}>
              <Text style={styles.masthead}>Notizie</Text>
              <View style={s.grow} />
              {newCount > 0 && (
                <Pressable onPress={showNew}>
                  <GlassView
                    glassEffectStyle="regular"
                    tintColor={theme.colors.accent}
                    isInteractive
                    style={styles.pillGlass}
                  >
                    <Text style={styles.newPillText}>{newCount} nuove</Text>
                  </GlassView>
                </Pressable>
              )}
            </View>

            {/* Ricerca */}
            <View style={{ marginTop: 12 }}>
              <TextInput
                value={query}
                onChangeText={setQuery}
                placeholder="Cerca…"
                autoCapitalize="sentences"
              />
            </View>

            {/* Progresso AI mentre il modello si prepara */}
            <AIBanner />

            {/* Due entrate minimal: prevendite e film in arrivo */}
            <View style={[s.row, { marginTop: 12, gap: 10 }]}>
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

            {/* Filtri fonte */}
            <View style={[s.row, { flexWrap: "wrap", marginTop: 12 }]}>
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
            </View>

            {error ? <Text style={styles.error}>{error}</Text> : null}
          </View>
        }
        ListEmptyComponent={
          loading ? (
            <Spinner label="Carico le notizie…" />
          ) : query.trim().length >= 2 ? (
            <EmptyState icon="🔍" title="Nessun risultato" subtitle="Prova con parole diverse." />
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

/** Piccola porta verso una pagina dedicata: icona, nome e conteggio. */
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
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [styles.entryCard, pressed && { opacity: 0.7 }]}
    >
      <Text style={styles.entryIcon}>{icon}</Text>
      <View style={s.grow}>
        <Text style={styles.entryLabel}>{label}</Text>
        <Text style={styles.entryCount}>
          {count > 0 ? count : "—"}
        </Text>
      </View>
      <Text style={styles.entryChevron}>›</Text>
    </Pressable>
  );
}

/** Thumbnail delle righe con fallback automatico. */
function RowImage({ uri }: { uri: string }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [uri]);
  if (failed) {
    return (
      <View style={[styles.rowThumb, styles.rowThumbEmpty]}>
        <Text style={{ fontSize: 18 }}>🎬</Text>
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
}

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
      {active ? (
        <View style={[styles.chip, styles.chipOn]}>
          <Text style={[styles.chipText, styles.chipTextOn]}>{label}</Text>
        </View>
      ) : (
        <GlassView glassEffectStyle="clear" isInteractive style={styles.chipGlass}>
          <Text style={styles.chipText}>{label}</Text>
        </GlassView>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: 16,
    paddingTop: 16,
    paddingBottom: 6,
  },
  masthead: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 34,
    fontWeight: "700",
    letterSpacing: -0.5,
    lineHeight: 40,
  },
  mastheadDate: {
    color: theme.colors.textDim,
    fontSize: 11,
    fontWeight: "600",
    marginLeft: 10,
    textTransform: "capitalize",
  },
  pillGlass: {
    borderRadius: 999,
    ...Platform.select({
      ios: {},
      default: { backgroundColor: theme.colors.accent },
    }),
  },
  newPillText: {
    color: theme.colors.bg,
    fontSize: 12,
    fontWeight: "700",
    paddingVertical: 6,
    paddingHorizontal: 12,
  },
  error: { color: theme.colors.warn, fontSize: 12, marginTop: 8, lineHeight: 17 },

  /* Entrate minimal */
  entryCard: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: theme.colors.surface,
    borderWidth: 1,
    borderColor: theme.colors.border,
    borderLeftWidth: 3,
    borderLeftColor: theme.colors.accent,
    borderRadius: theme.radius.md,
    paddingHorizontal: 14,
    paddingVertical: 12,
    gap: 10,
  },
  entryIcon: { fontSize: 20 },
  entryLabel: {
    color: theme.colors.textDim,
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 0.5,
    textTransform: "uppercase",
  },
  entryCount: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 22,
    fontWeight: "700",
    marginTop: 2,
    fontVariant: ["tabular-nums"],
  },
  entryChevron: {
    color: theme.colors.textDim,
    fontSize: 20,
    fontWeight: "300",
  },

  /* Righe minimal */
  rowCard: {
    flexDirection: "row",
    alignItems: "center",
    marginHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: theme.colors.border,
  },
  rowThumb: { width: 76, height: 56, borderRadius: theme.radius.xs },
  rowThumbEmpty: {
    backgroundColor: theme.colors.surfaceAlt,
    alignItems: "center",
    justifyContent: "center",
  },
  rowBody: { marginLeft: 12 },
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
    marginTop: 4,
  },
  savedMark: { color: theme.colors.ok, fontSize: 10, fontWeight: "700", marginTop: 3 },
  miniAction: {
    width: 30,
    height: 30,
    marginLeft: 8,
    marginRight: 6,
  },
  miniGlass: {
    width: 30,
    height: 30,
    borderRadius: 15,
    alignItems: "center" as const,
    justifyContent: "center" as const,
    ...Platform.select({
      ios: {},
      default: { backgroundColor: "rgba(255,255,255,0.10)" },
    }),
  },
  miniActionText: { color: theme.colors.textDim, fontSize: 16, fontWeight: "600" },
  aiActionText: { fontSize: 13 },
  time: { color: theme.colors.textDim, fontSize: 11 },

  chip: {
    paddingHorizontal: 11,
    paddingVertical: 5,
    borderRadius: 999,
    marginRight: 6,
    marginBottom: 6,
  },
  chipGlass: {
    borderRadius: 999,
    marginRight: 6,
    marginBottom: 6,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: "rgba(255,255,255,0.14)",
    ...Platform.select({
      ios: {},
      default: { backgroundColor: "rgba(255,255,255,0.10)" },
    }),
  },
  chipOn: { backgroundColor: theme.colors.text },
  chipText: {
    color: theme.colors.textDim,
    fontSize: 12,
    fontWeight: "600",
    paddingHorizontal: 11,
    paddingVertical: 5,
  },
  chipTextOn: { color: theme.colors.bg, fontWeight: "700" },
});
