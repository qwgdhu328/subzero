import React, { useCallback, useEffect, useState, useSyncExternalStore } from "react";
import {
  ActivityIndicator,
  Alert,
  Pressable,
  StyleSheet,
  Text,
  View,
} from "react-native";
import * as Haptics from "expo-haptics";
import { theme } from "../theme";
import { useStoreContext } from "../storage/StoreContext";
import {
  AI_MODELS,
  AIModelDef,
  cancelDownload,
  deleteModelFile,
  downloadModel,
  getAIState,
  getDownloadedModelPath,
  getAIModel,
  isDownloading,
  isExpoGo,
  loadEngine,
  retryAIBootstrap,
  subscribeAI,
  unloadEngine,
} from "../logic/localAI";
import { Button } from "./ui";

/**
 * Gestione dei modelli AI locali: download (~2-5 GB, con progresso),
 * selezione del modello attivo ed eliminazione per liberare spazio.
 */
export function AIModelManager({
  compact = false,
  onDownloaded,
}: {
  compact?: boolean;
  onDownloaded?: () => void;
}) {
  const { settings, update } = useStoreContext();
  const ai = useSyncExternalStore(subscribeAI, getAIState, getAIState);
  const selected = getAIModel(settings.aiModelKey);

  const [downloaded, setDownloaded] = useState<Set<string>>(new Set());
  const [progress, setProgress] = useState<Record<string, number>>({});
  const [busyKey, setBusyKey] = useState<string | null>(null);

  const refreshDownloaded = useCallback(async () => {
    const result = new Set<string>();
    for (const m of AI_MODELS) {
      if (await getDownloadedModelPath(m)) result.add(m.key);
    }
    setDownloaded(result);
  }, []);

  useEffect(() => {
    refreshDownloaded();
  }, [refreshDownloaded]);

  const doDownload = async (model: AIModelDef) => {
    setBusyKey(model.key);
    setProgress((p) => ({ ...p, [model.key]: 0 }));
    try {
      await downloadModel(model, (p) =>
        setProgress((prev) => ({ ...prev, [model.key]: p }))
      );
      await refreshDownloaded();
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      onDownloaded?.();
    } catch (e) {
      Alert.alert(
        "Download non riuscito",
        e instanceof Error ? e.message : "Controlla la connessione e riprova."
      );
    } finally {
      setBusyKey(null);
    }
  };

  const confirmDownload = (model: AIModelDef) => {
    Alert.alert(
      "Scaricare il modello AI?",
      `${model.name} · ${model.sizeGB.toFixed(1)} GB\n\nViene scaricato una sola volta e resta sul telefono: l'AI funziona anche offline e nessun dato viene inviato online.`,
      [
        { text: "Annulla", style: "cancel" },
        { text: "Scarica", onPress: () => doDownload(model) },
      ]
    );
  };

  const selectModel = async (model: AIModelDef) => {
    Haptics.selectionAsync();
    update({ aiModelKey: model.key });
    // Riavvia il bootstrap: se è scaricato carica, altrimenti scarica e carica
    retryAIBootstrap();
  };

  const removeModel = (model: AIModelDef) => {
    Alert.alert(
      "Eliminare il modello?",
      `${model.name}\n\nLiberi ${model.sizeGB.toFixed(1)} GB di spazio. Potrai riscaricarlo quando vuoi.`,
      [
        { text: "Annulla", style: "cancel" },
        {
          text: "Elimina",
          style: "destructive",
          onPress: async () => {
            if (isDownloading()) cancelDownload();
            await unloadEngine();
            await deleteModelFile(model);
            await refreshDownloaded();
          },
        },
      ]
    );
  };

  if (compact && downloaded.size === 0) return null;

  // In Expo Go il modulo nativo AI non esiste: niente download da 5 GB inutili
  if (isExpoGo()) {
    return (
      <View>
        <Text style={styles.dim}>
          ⚠️ L'AI locale funziona solo nell'app installata sul telefono
          (development build). In Expo Go il modulo AI nativo non è disponibile.
        </Text>
      </View>
    );
  }

  return (
    <View>
      {AI_MODELS.map((model) => {
        const has = downloaded.has(model.key);
        const isActive = model.key === selected.key && has;
        const prog = progress[model.key];
        const isBusy = busyKey === model.key;
        return (
          <View key={model.key} style={styles.modelRow}>
            <Pressable
              onPress={() => (has ? selectModel(model) : !isBusy && confirmDownload(model))}
              style={styles.modelInfo}
            >
              <View style={s2.row}>
                <Text style={styles.modelName}>{model.name}</Text>
                {isActive && <Text style={styles.activeTag}>IN USO</Text>}
                {has && !isActive && <Text style={styles.readyTag}>SCARICATO</Text>}
              </View>
              <Text style={styles.modelNote}>
                {model.sizeGB.toFixed(1)} GB · {model.note}
              </Text>
              {isBusy && prog != null && (
                <View style={styles.progressWrap}>
                  <View style={styles.progressTrack}>
                    <View
                      style={[
                        styles.progressFill,
                        { width: `${Math.round(prog * 100)}%` },
                      ]}
                    />
                  </View>
                  <Text style={styles.progressText}>
                    {Math.round(prog * 100)}%
                  </Text>
                </View>
              )}
            </Pressable>
            {isBusy ? (
              <Pressable onPress={cancelDownload} hitSlop={8} style={styles.modelAction}>
                <Text style={styles.cancelText}>✕</Text>
              </Pressable>
            ) : ai.phase === "loading" && isActive ? (
              <ActivityIndicator color={theme.colors.accent} size="small" />
            ) : has ? (
              <Pressable onPress={() => removeModel(model)} hitSlop={8} style={styles.modelAction}>
                <Text style={styles.trashText}>🗑</Text>
              </Pressable>
            ) : (
              <Pressable
                onPress={() => confirmDownload(model)}
                hitSlop={8}
                style={styles.downloadBtn}
              >
                <Text style={styles.downloadText}>↓ Scarica</Text>
              </Pressable>
            )}
          </View>
        );
      })}
      {!compact && (
        <Text style={styles.privacyNote}>
          🔒 L'AI gira sul tuo iPhone (llama.cpp): le notizie e i film che
          analizzi non vengono mai inviati online.
        </Text>
      )}
    </View>
  );
}

/** Card "AI" per la pagina Impostazioni: stato + gestione modelli. */
export function AISettingsCard() {
  const { settings, update } = useStoreContext();
  const ai = useSyncExternalStore(subscribeAI, getAIState, getAIState);

  const phaseLabel =
    ai.phase === "ready"
      ? "pronta ✓"
      : ai.phase === "downloading"
        ? `scarico ${Math.round(ai.progress * 100)}%`
        : ai.phase === "assembling"
          ? `assemblo ${Math.round(ai.progress * 100)}%`
          : ai.phase === "loading"
            ? "carico…"
            : ai.phase === "error"
              ? "errore"
              : "da scaricare";

  useEffect(() => {
    // All'apertura delle impostazioni: se l'AI è ferma, riprende il bootstrap
    if (ai.phase === "idle" && !settings.aiDisabled) retryAIBootstrap();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <View>
      <View style={[s2.row, { marginBottom: 8 }]}>
        <Text style={[s2.sectionTitle, { marginBottom: 0, flex: 1 }]}>AI locale ✨</Text>
        <Text style={styles.statusText}>{phaseLabel}</Text>
      </View>
      <Text style={styles.dim}>
        Un assistente che spiega le notizie e i film in parole semplici, tutto
        in italiano. Il modello gira sul telefono: funziona anche senza rete.
      </Text>
      <View style={{ height: 10 }} />
      <AIModelManager />
      <View style={{ height: 8 }} />
      <Button
        label={settings.aiDisabled ? "Riattiva i pulsanti ✨ nell'app" : "Disattiva l'AI nell'app"}
        variant="ghost"
        onPress={() => {
          Haptics.selectionAsync();
          update({ aiDisabled: !settings.aiDisabled });
        }}
      />
    </View>
  );
}

const s2 = {
  row: { flexDirection: "row" as const, alignItems: "center" as const },
  sectionTitle: {
    color: theme.colors.textDim,
    fontSize: 12,
    fontWeight: "800" as const,
    letterSpacing: 1.2,
    textTransform: "uppercase" as const,
    marginBottom: 6,
  },
};

const styles = StyleSheet.create({
  modelRow: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: theme.colors.border,
  },
  modelInfo: { flex: 1, paddingRight: 8 },
  modelName: { color: theme.colors.text, fontSize: 15, fontWeight: "700" },
  modelNote: { color: theme.colors.textDim, fontSize: 12, marginTop: 2 },
  activeTag: {
    color: theme.colors.bg,
    backgroundColor: theme.colors.accent,
    fontSize: 9,
    fontWeight: "800",
    letterSpacing: 0.8,
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 6,
    marginLeft: 8,
    overflow: "hidden",
  },
  readyTag: {
    color: theme.colors.ok,
    fontSize: 9,
    fontWeight: "800",
    letterSpacing: 0.8,
    marginLeft: 8,
  },
  statusText: { color: theme.colors.textDim, fontSize: 11, fontWeight: "700" },
  progressWrap: { flexDirection: "row", alignItems: "center", marginTop: 8 },
  progressTrack: {
    flex: 1,
    height: 6,
    borderRadius: 3,
    backgroundColor: theme.colors.surfaceAlt,
    overflow: "hidden",
  },
  progressFill: {
    height: 6,
    backgroundColor: theme.colors.accent,
    borderRadius: 3,
  },
  progressText: {
    color: theme.colors.textDim,
    fontSize: 11,
    fontWeight: "700",
    marginLeft: 8,
    width: 38,
    textAlign: "right",
  },
  modelAction: { width: 40, alignItems: "center" },
  trashText: { fontSize: 16 },
  cancelText: { color: theme.colors.danger, fontSize: 16, fontWeight: "700" },
  downloadBtn: {
    paddingHorizontal: 10,
    paddingVertical: 7,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.accent + "66",
  },
  downloadText: { color: theme.colors.accent, fontSize: 12, fontWeight: "700" },
  privacyNote: {
    color: theme.colors.textDim,
    fontSize: 11,
    lineHeight: 16,
    marginTop: 10,
  },
  dim: { color: theme.colors.textDim, fontSize: 13, lineHeight: 19 },
});
