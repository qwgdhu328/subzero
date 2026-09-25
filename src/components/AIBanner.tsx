import React, { useSyncExternalStore } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { useRouter } from "expo-router";
import { theme } from "../theme";
import { getAIState, subscribeAI } from "../logic/localAI";

/**
 * Mini banner di progresso AI per la home: compare solo mentre il modello
 * si scarica/carica e sparisce da solo quando l'AI è pronta. Un tocco apre
 * la pagina AI con i dettagli.
 */
export function AIBanner() {
  const ai = useSyncExternalStore(subscribeAI, getAIState, getAIState);
  const router = useRouter();

  const active =
    ai.phase === "downloading" ||
    ai.phase === "assembling" ||
    ai.phase === "loading";
  if (!active) return null;

  const label =
    ai.phase === "downloading"
      ? `Preparo l'AI… ${Math.round(ai.progress * 100)}%`
      : ai.phase === "assembling"
        ? "AI: assemblo il file…"
        : "Preparo l'AI…";

  return (
    <Pressable
      onPress={() => router.push("/ai")}
      style={({ pressed }) => [styles.banner, pressed && { opacity: 0.85 }]}
    >
      <Text style={styles.icon}>✨</Text>
      <View style={styles.grow}>
        <Text style={styles.text}>{label}</Text>
        <View style={styles.track}>
          <View
            style={[
              styles.fill,
              {
                width:
                  ai.phase === "downloading" || ai.phase === "assembling"
                    ? `${Math.max(3, Math.round(ai.progress * 100))}%`
                    : "100%",
                opacity: ai.phase === "downloading" ? 1 : 0.45,
              },
            ]}
          />
        </View>
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  banner: {
    flexDirection: "row",
    alignItems: "center",
    marginTop: 10,
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: theme.radius.sm,
    backgroundColor: theme.colors.surface,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
  },
  icon: { fontSize: 14, marginRight: 10 },
  grow: { flex: 1 },
  text: {
    color: theme.colors.textDim,
    fontSize: 12,
    fontWeight: "700",
    marginBottom: 5,
  },
  track: {
    height: 3,
    borderRadius: 2,
    backgroundColor: theme.colors.surfaceAlt,
    overflow: "hidden",
  },
  fill: { height: 3, backgroundColor: theme.colors.accent, borderRadius: 2 },
});
