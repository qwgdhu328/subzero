import React, { useState } from "react";
import { Linking, Platform, Pressable, Share, StyleSheet, Text, View } from "react-native";
import { GlassView } from "expo-glass-effect";
import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import { WebView } from "react-native-webview";
import * as Haptics from "expo-haptics";
import { theme } from "../src/theme";
import { styles as s } from "../src/theme";
import { LiquidButton } from "../src/components/ui";
import { useStoreContext } from "../src/storage/StoreContext";
import { fetchArticleText } from "../src/logic/news";

/**
 * Domini pubblicitari/tracking bloccati a livello di navigazione:
 * la WebView rifiuta di caricare qualsiasi richiesta verso questi host.
 */
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
  "adsystem.com",
  "scorecardresearch.com",
  "quantserve.com",
  "adsafeprotected.com",
  "moatads.com",
  "zedo.com",
  "adroll.com",
  "bidswitch.net",
  "casalemedia.com",
  "openx.net",
  "2mdn.net",
  "gtagjs.js",
];

/**
 * JS iniettato a ogni caricamento: nasconde gli slot pubblicitari già
 * presenti nel DOM e rimuove gli iframe dei network più comuni.
 */
const AD_BLOCK_JS = `
(function() {
  try {
    var css = '[id^="div-gpt-ad"],[id^="taboola"],[class*="taboola"],[class*="advert"],[class*="adv-box"],[class*="ad_slot"],[class*="adsbygoogle"],[class*="adv_"][class*="-adv"],[id*="banner-ad"],[data-ad],iframe[src*="doubleclick"],iframe[src*="googlesyndication"],iframe[src*="taboola"],iframe[src*="outbrain"],iframe[src*="amazon-adsystem"] { display: none !important; height: 0 !important; }';
    var style = document.createElement('style');
    style.id = 'cineflash-adblock';
    style.textContent = css;
    document.head.appendChild(style);
    document.querySelectorAll('iframe[src*="doubleclick"],iframe[src*="googlesyndication"],iframe[src*="taboola"],iframe[src*="outbrain"],iframe[src*="amazon-adsystem"]').forEach(function(el){ el.remove(); });
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
  const [aiPreparing, setAiPreparing] = useState(false);

  const aiEnabled = !settings.aiDisabled;

  /** Apre la pagina AI passando il testo reale dell'articolo come contesto. */
  const openAI = async () => {
    if (!uri) return;
    Haptics.selectionAsync();
    setAiPreparing(true);
    // Estrae il testo dell'articolo (best effort): anche null va bene,
    // l'AI lavorerà con titolo e fonte.
    const articleText = await fetchArticleText(uri);
    setAiPreparing(false);
    router.push({
      pathname: "/ai",
      params: {
        mode: "news",
        title: title ?? "",
        source: source ?? "",
        text: articleText ?? `${title ?? ""}. Fonte: ${source ?? ""}.`,
      },
    });
  };

  const share = async () => {
    if (uri) {
      try {
        await Share.share({ message: `${title ?? ""}\n${uri}` });
      } catch {}
    }
  };

  if (!uri) {
    return (
      <View style={[s.screen, styles.center]}>
        <Text style={styles.errText}>Link non valido.</Text>
      </View>
    );
  }

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
              {aiEnabled && (
                <Pressable onPress={openAI} hitSlop={10} style={styles.hBtn}>
                  <GlassView glassEffectStyle="clear" isInteractive style={styles.hBtnGlass}>
                    <Text style={styles.hBtnText}>✨</Text>
                  </GlassView>
                </Pressable>
              )}
              <Pressable onPress={share} hitSlop={10} style={styles.hBtn}>
                <GlassView glassEffectStyle="clear" isInteractive style={styles.hBtnGlass}>
                  <Text style={styles.hBtnText}>↗</Text>
                </GlassView>
              </Pressable>
              <Pressable
                onPress={() => {
                  if (uri) Linking.openURL(uri).catch(() => {});
                }}
                hitSlop={10}
                style={styles.hBtn}
              >
                <GlassView glassEffectStyle="clear" isInteractive style={styles.hBtnGlass}>
                  <Text style={[styles.hBtnText, { fontSize: 11 }]}>Safari</Text>
                </GlassView>
              </Pressable>
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

      {/* Pulsante flottante liquid glass: "Spiega con l'AI" */}
      {aiEnabled && (
        <View style={styles.aiFabWrap} pointerEvents="box-none">
          <LiquidButton
            label={aiPreparing ? "… preparo l'AI" : "✨ Spiega con l'AI"}
            onPress={openAI}
            filled
          />
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: "center", justifyContent: "center" },
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
      default: { backgroundColor: "rgba(255,255,255,0.10)" },
    }),
  },
  hBtnText: { color: theme.colors.accent, fontSize: 16, fontWeight: "700" },
  web: { flex: 1, backgroundColor: theme.colors.bg },
  aiFabWrap: {
    position: "absolute",
    bottom: 24,
    alignSelf: "center",
  },
});
