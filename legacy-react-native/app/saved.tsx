import React, { useCallback } from "react";
import {
  Alert,
  FlatList,
  Platform,
  Pressable,
  Share,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { GlassView } from "expo-glass-effect";
import { Stack, useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { theme, fonts } from "../src/theme";
import { styles as s } from "../src/theme";
import { useStoreContext } from "../src/storage/StoreContext";
import { SavedNewsItem } from "../src/storage/collections";
import { timeAgo } from "../src/logic/news";
import { Badge, EmptyState, Spinner } from "../src/components/ui";

/**
 * Pagina "Salvati": le notizie che l'utente ha archiviato con il bottone ＋
 * dalla home. Tap → articolo; pressione lunga → rimozione; bottone → condivisione.
 */
export default function SavedScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { savedNews } = useStoreContext();

  const open = useCallback(
    (item: SavedNewsItem) => {
      Haptics.selectionAsync();
      router.push({
        pathname: "/article",
        params: { url: item.link, title: item.title, source: item.source },
      });
    },
    [router]
  );

  const share = useCallback(async (item: SavedNewsItem) => {
    Haptics.selectionAsync();
    try {
      await Share.share({ message: `${item.title}\n${item.link}` });
    } catch {}
  }, []);

  const remove = useCallback(
    (item: SavedNewsItem) => {
      Alert.alert("Rimuovere dai salvati?", item.title, [
        { text: "Annulla", style: "cancel" },
        {
          text: "Rimuovi",
          style: "destructive",
          onPress: () => savedNews.toggle(item),
        },
      ]);
    },
    [savedNews]
  );

  const renderItem = useCallback(
    ({ item }: { item: SavedNewsItem }) => (
      <SavedRow
        item={item}
        onOpen={() => open(item)}
        onShare={() => share(item)}
        onRemove={() => remove(item)}
      />
    ),
    [open, share, remove]
  );

  return (
    <View style={s.screen}>
      <Stack.Screen options={{ headerShown: false }} />
      <FlatList
        data={savedNews.saved}
        keyExtractor={(x) => x.id}
        renderItem={renderItem}
        contentContainerStyle={{ paddingBottom: 40 + insets.bottom }}
        ListHeaderComponent={
          <View>
            <View style={[styles.header, { paddingTop: 14 + insets.top }]}>
              <PressableBack onPress={() => router.back()} />
            </View>
            <View style={styles.masthead}>
              <Text style={s.eyebrow}>CineFlash · Da leggere</Text>
              <Text style={styles.pageTitle}>Salvati</Text>
              {savedNews.saved.length > 0 ? (
                <Text style={styles.count}>
                  {savedNews.saved.length}{" "}
                  {savedNews.saved.length === 1 ? "notizia archiviata" : "notizie archiviate"}
                </Text>
              ) : null}
            </View>
          </View>
        }
        ListEmptyComponent={
          savedNews.ready ? (
            <EmptyState
              icon="🔖"
              title="Nessuna notizia salvata"
              subtitle="Tocca ＋ su una notizia in home per archiviarla qui: la ritrovi anche offline."
            />
          ) : (
            <Spinner label="Carico i salvati…" />
          )
        }
      />
    </View>
  );
}

/** Riga di salvato: tap apre, pressione lunga rimuove, bottone condivide. */
function SavedRow({
  item,
  onOpen,
  onShare,
  onRemove,
}: {
  item: SavedNewsItem;
  onOpen: () => void;
  onShare: () => void;
  onRemove: () => void;
}) {
  return (
    <Pressable
      onPress={onOpen}
      onLongPress={onRemove}
      delayLongPress={400}
      style={({ pressed }) => [styles.row, pressed && { opacity: 0.75 }]}
    >
      <View style={[styles.thumb, styles.thumbEmpty]}>
        <Text style={{ fontSize: 20 }}>🔖</Text>
      </View>
      <View style={s.grow}>
        <View style={s.row}>
          <Badge label="SALVATO" tone="ok" />
          <Text style={styles.savedAt} numberOfLines={1}>
            {"  "}
            {timeAgo(item.savedAt)}
          </Text>
        </View>
        <Text style={styles.rowTitle} numberOfLines={2}>
          {item.title}
        </Text>
        <Text style={styles.rowSource} numberOfLines={1}>
          {item.source}
          {item.publishedAt ? ` · ${timeAgo(item.publishedAt)}` : ""}
        </Text>
      </View>
      <Pressable
        onPress={onShare}
        hitSlop={8}
        style={({ pressed }) => [styles.miniBtn, pressed && { opacity: 0.7 }]}
      >
        <Text style={styles.miniText}>↗</Text>
      </Pressable>
    </Pressable>
  );
}

function PressableBack({ onPress }: { onPress: () => void }) {
  return (
    <Pressable onPress={onPress} hitSlop={10}>
      <GlassView glassEffectStyle="clear" isInteractive style={styles.backBtn}>
        <Text style={styles.backText}>‹</Text>
      </GlassView>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  header: { paddingHorizontal: 16, paddingTop: 14 },
  backBtn: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: "center",
    justifyContent: "center",
    ...Platform.select({
      ios: {},
      default: { backgroundColor: theme.colors.surfaceAlt },
    }),
  },
  backText: {
    color: theme.colors.text,
    fontSize: 24,
    fontWeight: "700",
    marginTop: -2,
  },
  masthead: { paddingHorizontal: 16, paddingTop: 10, paddingBottom: 14 },
  pageTitle: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 32,
    fontWeight: "700",
    letterSpacing: -0.5,
    marginTop: 4,
  },
  count: {
    color: theme.colors.textDim,
    fontSize: 12,
    fontWeight: "600",
    marginTop: 4,
  },
  row: {
    flexDirection: "row",
    alignItems: "center",
    marginHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: theme.colors.border,
    gap: 12,
  },
  thumb: {
    width: 56,
    height: 56,
    borderRadius: theme.radius.xs,
    backgroundColor: theme.colors.surfaceAlt,
  },
  thumbEmpty: { alignItems: "center", justifyContent: "center" },
  savedAt: { color: theme.colors.textDim, fontSize: 11, fontWeight: "600", flexShrink: 1 },
  rowTitle: {
    color: theme.colors.text,
    fontSize: 15,
    fontWeight: "600",
    lineHeight: 20,
    marginTop: 4,
  },
  rowSource: { color: theme.colors.textDim, fontSize: 11, marginTop: 3 },
  miniBtn: {
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: "center",
    justifyContent: "center",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    backgroundColor: theme.colors.surfaceAlt,
  },
  miniText: { color: theme.colors.textDim, fontSize: 14, fontWeight: "700" },
});
