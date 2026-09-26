import React, { useEffect, useRef, useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { Stack, useLocalSearchParams } from "expo-router";
import * as Haptics from "expo-haptics";
import { theme } from "../src/theme";
import { styles as s } from "../src/theme";
import { ChatView } from "../src/components/ChatView";

/**
 * Pagina AI dedicata: wrapper di ChatView con banner di contesto (notizia o
 * film) e primo messaggio guidato via seed. Tutto il resto della chat vive
 * nel componente condiviso.
 */
export default function AIScreen() {
  const params = useLocalSearchParams<{
    mode?: string;
    title?: string;
    text?: string;
    source?: string;
  }>();

  const mode = params.mode === "movie" ? "movie" : "news";
  const context = {
    title: params.title ?? undefined,
    text: params.text ?? undefined,
    source: params.source ?? undefined,
  };

  /** Primo messaggio guidato: parte una sola volta, alla prima apertura. */
  const [seed, setSeed] = useState<{ title: string; text: string } | undefined>(undefined);
  const [seedNonce, setSeedNonce] = useState(0);
  /** "Nuova chat": incrementa per svuotare la conversazione in ChatView. */
  const [resetNonce, setResetNonce] = useState(0);
  const askedRef = useRef(false);
  useEffect(() => {
    if (askedRef.current || !context.text) return;
    askedRef.current = true;
    setSeed({
      title: context.title ?? "",
      text:
        mode === "news"
          ? `Spiegami in parole semplici questa notizia: cosa succede e perché è importante?`
          : `Presentami questo film in modo semplice: di cosa parla la trama e perché vale la pena vederlo?`,
    });
    setSeedNonce((n) => n + 1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const resetChat = () => {
    Haptics.selectionAsync();
    setResetNonce((n) => n + 1);
  };

  return (
    <View style={s.screen}>
      <Stack.Screen
        options={{
          headerShown: true,
          headerTitle: `✨ AI · ${mode === "news" ? "Notizia" : "Film"}`,
          headerTitleStyle: styles.headerTitle,
          headerTintColor: theme.colors.accent,
          headerShadowVisible: false,
          headerBackTitle: "Indietro",
          headerStyle: { backgroundColor: theme.colors.bg },
        }}
      />

      {context.title ? (
        <View style={styles.ctxBanner}>
          <View style={s.grow}>
            <Text style={styles.ctxLabel}>{mode === "news" ? "NOTIZIA" : "FILM"}</Text>
            <Text style={styles.ctxTitle} numberOfLines={2}>
              {context.title}
            </Text>
          </View>
          <Pressable onPress={resetChat} hitSlop={8} style={styles.resetChip}>
            <Text style={styles.resetText}>↺ Nuova chat</Text>
          </Pressable>
        </View>
      ) : null}

      <View style={styles.chatArea}>
        <ChatView context={context} seed={seed} seedNonce={seedNonce} resetNonce={resetNonce} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  headerTitle: { color: theme.colors.text, fontSize: 16, fontWeight: "700" },
  ctxBanner: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: theme.colors.border,
    backgroundColor: theme.colors.surface,
    gap: 10,
  },
  resetChip: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    backgroundColor: theme.colors.surfaceAlt,
  },
  resetText: { color: theme.colors.accent, fontSize: 11, fontWeight: "800" },
  ctxLabel: {
    color: theme.colors.accent,
    fontSize: 10,
    fontWeight: "800",
    letterSpacing: 1,
  },
  ctxTitle: { color: theme.colors.text, fontSize: 14, fontWeight: "700", marginTop: 3 },
  chatArea: { flex: 1 },
});
