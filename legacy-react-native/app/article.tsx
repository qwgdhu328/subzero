import React, { useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  Animated,
  Image,
  NativeSyntheticEvent,
  NativeScrollEvent,
  Platform,
  Pressable,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { GlassView } from "expo-glass-effect";
import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import { WebView } from "react-native-webview";
import * as Haptics from "expo-haptics";
import { theme, fonts } from "../src/theme";
import { styles as s } from "../src/theme";
import { LiquidButton, Badge } from "../src/components/ui";
import { useStoreContext } from "../src/storage/StoreContext";
import { fetchArticleText } from "../src/logic/news";
import { articleIdFor, getAiArticle, AiArticle } from "../src/logic/aiNews";

/* ---------- Blocco pubblicità per il fallback WebView ---------- */

const AD_HOSTS = [
  "doubleclick.net",
  "googlesyndication.com",
  "google-analytics.com",
  "googletagmanager.com",
  "googleadservices.com",
  "taboola.com",
  "outbrain.com",
  "amazon-adsystem.com",
  "criteo.com",
  "criteo.net",
  "smartadserver.com",
  "pubmatic.com",
  "rubiconproject.com",
  "adnxs.com",
  "scorecardresearch.com",
  "quantserve.com",
  "openx.net",
  "2mdn.net",
];

const AD_BLOCK_JS = `
(function() {
  try {
    var css = '[id^="div-gpt-ad"],[id^="taboola"],[class*="taboola"],[class*="advert"],[class*="adsbygoogle"],[data-ad],iframe[src*="doubleclick"],iframe[src*="googlesyndication"],iframe[src*="taboola"],iframe[src*="outbrain"] { display: none !important; height: 0 !important; }';
    var style = document.createElement('style');
    style.id = 'cineflash-adblock';
    style.textContent = css;
    document.head.appendChild(style);
  } catch (e) {}
})();
true;
`;

export default function ArticleScreen() {
  const { url, title, source } = useLocalSearchParams<{
    url: string;
    title?: string;
    source?: string;
  }>();
  const uri = typeof url === "string" && url.startsWith("http") ? url : null;

  const { settings } = useStoreContext();
  const router = useRouter();

  /* Articolo AI: caricato dall'id stabile della notizia. Se il feed arriva
  mentre la pagina è già aperta, un leggero poll recupera la riscrittura. */
  const [art, setArt] = useState<AiArticle | null>(null);
  const [waiting, setWaiting] = useState(true);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const [showOriginal, setShowOriginal] = useState(false);

  /* Avanzamento di lettura: 0→1 mentre si scorre l'articolo AI. Un solo
  Animated.Value aggiornato via onScroll, zero re-render JS. */
  const progress = useRef(new Animated.Value(0)).current;
  const onScroll = (e: NativeSyntheticEvent<NativeScrollEvent>) => {
    const c = e.nativeEvent.contentOffset.y;
    const max = Math.max(1, e.nativeEvent.contentSize.height - e.nativeEvent.layoutMeasurement.height);
    progress.setValue(Math.min(1, Math.max(0, c / max)));
  };

  const id = uri ? articleIdFor(uri) : null;

  useEffect(() => {
    if (!id) {
      setWaiting(false);
      return;
    }
    let alive = true;
    let tries = 0;
    const check = async () => {
      const a = await getAiArticle(id);
      if (!alive) return;
      if (a) {
        setArt(a);
        setWaiting(false);
        if (pollRef.current) clearInterval(pollRef.current);
      } else {
        tries += 1;
        // Dopo ~20s di attesa senza riscrittura, proponi il fallback
        if (tries > 10) setWaiting(false);
      }
    };
    check();
    pollRef.current = setInterval(check, 2000);
    return () => {
      alive = false;
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, [id]);

  const openAI = async () => {
    if (!uri) return;
    Haptics.selectionAsync();
    const text = art
      ? `${art.title}. ${art.standfirst} ${art.paragraphs.join(" ")}`
      : await fetchArticleText(uri);
    router.push({
      pathname: "/ai",
      params: {
        mode: "news",
        title: art?.title ?? title ?? "",
        source: source ?? "",
        text: text ?? `${title ?? ""}. Fonte: ${source ?? ""}.`,
      },
    });
  };

  const share = async () => {
    if (!uri) return;
    try {
      await Share.share({
        message: `${art?.title ?? title ?? ""}\n${art?.sourceUrl ?? uri}`,
      });
    } catch {}
  };

  if (!uri) {
    return (
      <View style={[s.screen, styles.center]}>
        <Text style={styles.errText}>Link non valido.</Text>
      </View>
    );
  }

  /* ---------- Vista articolo AI ---------- */
  if (art && !showOriginal) {
    const hero = art.images[0] ?? null;
    const gallery = art.images.slice(1, 6);
    return (
      <View style={s.screen}>
        <Stack.Screen
          options={{
            headerShown: true,
            headerTitle: "CineFlash",
            headerTitleStyle: styles.headerTitle,
            headerTintColor: theme.colors.accent,
            headerShadowVisible: false,
            headerBackTitle: "Indietro",
            headerStyle: { backgroundColor: theme.colors.bg },
            headerRight: () => (
              <View style={s.row}>
                <Pressable onPress={share} hitSlop={10} style={styles.hBtn}>
                  <GlassView glassEffectStyle="clear" isInteractive style={styles.hBtnGlass}>
                    <Text style={styles.hBtnText}>↗</Text>
                  </GlassView>
                </Pressable>
                <Pressable
                  onPress={() => {
                    Haptics.selectionAsync();
                    setShowOriginal(true);
                  }}
                  hitSlop={10}
                  style={styles.hBtn}
                >
                  <GlassView glassEffectStyle="clear" isInteractive style={styles.hBtnGlass}>
                    <Text style={[styles.hBtnText, { fontSize: 11 }]}>Fonte</Text>
                  </GlassView>
                </Pressable>
              </View>
            ),
          }}
        />
        <ScrollView contentContainerStyle={styles.articleWrap} onScroll={onScroll} scrollEventThrottle={16}>
          <Animated.View
            pointerEvents="none"
            style={[
              styles.readProgress,
              {
                width: progress.interpolate({
                  inputRange: [0, 1],
                  outputRange: ["0%", "100%"],
                }),
              },
            ]}
          />
          <View style={s.row}>
            <Badge label="✦ ARTICOLO" tone="accent" />
            <Text style={styles.srcLabel}>{art.source}</Text>
            <View style={s.grow} />
            <Text style={styles.time}>{timeLabel(art.publishedAt)}</Text>
          </View>

          <Text style={styles.headline}>{art.title}</Text>
          {art.standfirst ? (
            <Text style={styles.standfirst}>{art.standfirst}</Text>
          ) : null}

          {hero ? (
            <Image source={{ uri: hero }} style={styles.hero} resizeMode="cover" />
          ) : null}

          <View style={styles.body}>
            {art.paragraphs.map((p, i) => (
              <Text key={i} style={styles.para}>
                {p}
              </Text>
            ))}
          </View>

          {gallery.length > 0 ? (
            <View style={styles.gallery}>
              <Text style={styles.galleryLabel}>Dall'articolo originale</Text>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.galleryRow}>
                {gallery.map((g, i) => (
                  <Image key={i} source={{ uri: g }} style={styles.galleryImg} resizeMode="cover" />
                ))}
              </ScrollView>
            </View>
          ) : null}

          <Text style={styles.foot}>
           Articolo redatto con l'AI di CineFlash a partire da una notizia di{" "}
            {art.source}. Vuoi l'originale? Tocca “Fonte” in alto.
          </Text>
        </ScrollView>

        <View style={styles.aiFabWrap} pointerEvents="box-none">
          <LiquidButton label="✨ Chiedi all'AI" onPress={openAI} filled />
        </View>
      </View>
    );
  }

  /* ---------- In attesa della redazione AI ---------- */
  if (waiting) {
    return (
      <View style={s.screen}>
        <Stack.Screen
          options={{
            headerShown: true,
            headerTitle: (source as string) ?? "",
            headerTitleStyle: styles.headerTitle,
            headerTintColor: theme.colors.accent,
            headerShadowVisible: false,
            headerBackTitle: "Indietro",
            headerStyle: { backgroundColor: theme.colors.bg },
          }}
        />
        <View style={styles.center}>
          <ActivityIndicator color={theme.colors.accent} size="large" />
          <Text style={styles.waitTitle}>La redazione sta scrivendo l'articolo…</Text>
          <Text style={styles.waitSub}>
            Stiamo riscrivendo la notizia in parole chiare. Ci vuole poco.
          </Text>
          <Pressable
            onPress={() => {
              Haptics.selectionAsync();
              setShowOriginal(true);
            }}
            style={{ marginTop: 18 }}
          >
            <GlassView glassEffectStyle="clear" isInteractive style={styles.fallbackPill}>
              <Text style={styles.fallbackText}>Leggi l'originale intanto</Text>
            </GlassView>
          </Pressable>
        </View>
      </View>
    );
  }

  /* ---------- Fallback: sito originale in WebView ---------- */
  return (
    <View style={s.screen}>
      <Stack.Screen
        options={{
          headerShown: true,
          headerTitle: (source as string) ?? "",
          headerTitleStyle: styles.headerTitle,
          headerTintColor: theme.colors.accent,
          headerShadowVisible: false,
          headerBackTitle: "Indietro",
          headerStyle: { backgroundColor: theme.colors.bg },
          headerRight: () => (
            <View style={s.row}>
              <Pressable onPress={share} hitSlop={10} style={styles.hBtn}>
                <GlassView glassEffectStyle="clear" isInteractive style={styles.hBtnGlass}>
                  <Text style={styles.hBtnText}>↗</Text>
                </GlassView>
              </Pressable>
              {art ? (
                <Pressable
                  onPress={() => {
                    Haptics.selectionAsync();
                    setShowOriginal(false);
                  }}
                  hitSlop={10}
                  style={styles.hBtn}
                >
                  <GlassView glassEffectStyle="clear" isInteractive style={styles.hBtnGlass}>
                    <Text style={[styles.hBtnText, { fontSize: 11 }]}>✦</Text>
                  </GlassView>
                </Pressable>
              ) : null}
            </View>
          ),
        }}
      />
      <WebView
        source={{ uri }}
        style={styles.web}
        setSupportMultipleWindows={false}
        injectedJavaScript={AD_BLOCK_JS}
        onShouldStartLoadWithRequest={(req) => {
          try {
            const host = new URL(req.url).hostname;
            if (AD_HOSTS.some((d) => host.endsWith(d))) return false;
          } catch {}
          return true;
        }}
      />
    </View>
  );
}

function timeLabel(iso: string | null): string {
  if (!iso) return "";
  const diff = Date.now() - Date.parse(iso);
  if (isNaN(diff) || diff < 0) return "";
  const min = Math.floor(diff / 60_000);
  if (min < 1) return "adesso";
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `${h} ${h === 1 ? "ora" : "ore"}`;
  return new Date(iso).toLocaleDateString("it-IT", { day: "numeric", month: "short" });
}

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 32 },
  errText: { color: theme.colors.textDim, fontSize: 14 },
  headerTitle: { color: theme.colors.text, fontSize: 16, fontWeight: "700" },
  hBtn: { marginLeft: 8 },
  hBtnGlass: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: "center" as const,
    justifyContent: "center" as const,
    ...Platform.select({
      ios: {},
      default: { backgroundColor: theme.colors.surfaceAlt },
    }),
  },
  hBtnText: { color: theme.colors.accent, fontSize: 16, fontWeight: "700" },

  /* Articolo AI */
  articleWrap: { padding: 16, paddingBottom: 120 },
  readProgress: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    height: 2,
    borderRadius: 1,
    backgroundColor: theme.colors.accent + "AA",
  },
  srcLabel: {
    color: theme.colors.textDim,
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 1,
    textTransform: "uppercase",
    marginLeft: 8,
  },
  time: { color: theme.colors.textDim, fontSize: 11, fontWeight: "600" },
  headline: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 26,
    fontWeight: "700",
    lineHeight: 31,
    letterSpacing: -0.4,
    marginTop: 10,
  },
  standfirst: {
    color: theme.colors.textDim,
    fontSize: 16,
    lineHeight: 23,
    marginTop: 8,
    fontStyle: "italic",
  },
  hero: {
    width: "100%",
    aspectRatio: 16 / 9,
    borderRadius: theme.radius.md,
    marginTop: 14,
    backgroundColor: theme.colors.surfaceAlt,
  },
  body: { marginTop: 18 },
  para: {
    color: theme.colors.text,
    fontSize: 16,
    lineHeight: 25,
    marginBottom: 14,
  },
  gallery: { marginTop: 10 },
  galleryLabel: {
    color: theme.colors.textDim,
    fontSize: 11,
    fontWeight: "800",
    letterSpacing: 2,
    textTransform: "uppercase",
    marginBottom: 8,
  },
  galleryRow: { gap: 10 },
  galleryImg: {
    width: 220,
    height: 140,
    borderRadius: theme.radius.sm,
    backgroundColor: theme.colors.surfaceAlt,
  },
  foot: {
    color: theme.colors.textDim,
    fontSize: 12,
    lineHeight: 18,
    marginTop: 16,
    fontStyle: "italic",
  },
  aiFabWrap: { position: "absolute", bottom: 24, alignSelf: "center" },

  /* Attesa redazione */
  waitTitle: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 20,
    fontWeight: "700",
    textAlign: "center",
    marginTop: 16,
  },
  waitSub: {
    color: theme.colors.textDim,
    fontSize: 14,
    textAlign: "center",
    marginTop: 8,
    lineHeight: 20,
  },
  fallbackPill: {
    borderRadius: 999,
    ...Platform.select({
      ios: {},
      default: { backgroundColor: theme.colors.surfaceAlt },
    }),
  },
  fallbackText: {
    color: theme.colors.accent,
    fontSize: 13,
    fontWeight: "700",
    paddingVertical: 10,
    paddingHorizontal: 18,
  },

  web: { flex: 1, backgroundColor: theme.colors.bg },
});
