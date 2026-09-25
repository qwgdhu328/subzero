import React, { useCallback, useEffect, useRef, useState, useSyncExternalStore } from "react";
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput as RNTextInput,
  View,
  type ScrollViewInstance,
} from "react-native";
import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import { GlassView } from "expo-glass-effect";
import { theme } from "../src/theme";
import { styles as s } from "../src/theme";
import { useStoreContext } from "../src/storage/StoreContext";
import {
  ChatMessage,
  chat,
  getAIModel,
  getAIState,
  retryAIBootstrap,
  stopChat,
  subscribeAI,
} from "../src/logic/localAI";

type AIMode = "news" | "movie";

/**
 * Pagina AI: chat con il modello locale (llama.cpp) che spiega notizie e film.
 * Se il modello non è ancora pronto (primo avvio: download in corso), mostra
 * una schermata "in manutenzione" che si sblocca da sola quando l'AI è pronta.
 */
export default function AIScreen() {
  const params = useLocalSearchParams<{
    mode?: string;
    title?: string;
    text?: string;
    source?: string;
  }>();

  const mode: AIMode = params.mode === "movie" ? "movie" : "news";
  const context = {
    title: params.title ?? undefined,
    text: params.text ?? undefined,
    source: params.source ?? undefined,
  };

  const { settings } = useStoreContext();
  const router = useRouter();
  const model = getAIModel(settings.aiModelKey);

  // Stato globale dell'AI (bootstrap automatico avviato all'avvio dell'app)
  const ai = useSyncExternalStore(subscribeAI, getAIState, getAIState);
  const ready = ai.phase === "ready";
  const maintenance =
    ai.phase === "idle" ||
    ai.phase === "downloading" ||
    ai.phase === "assembling" ||
    ai.phase === "loading";

  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [streaming, setStreaming] = useState(false);
  const [streamText, setStreamText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const scrollRef = useRef<ScrollViewInstance>(null);

  // La prima domanda guidata parte da sola quando l'AI si sblocca
  const askedRef = useRef(false);

  // (Ri)parte il bootstrap se la pagina viene aperta con l'AI ferma
  useEffect(() => {
    if (ai.phase === "idle") retryAIBootstrap();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ai.phase]);

  // Primo messaggio automatico appena l'AI diventa pronta
  useEffect(() => {
    if (ready && !askedRef.current && context.text) {
      askedRef.current = true;
      const first =
        mode === "news"
          ? `Spiegami in parole semplici questa notizia: cosa succede e perché è importante?`
          : `Presentami questo film in modo semplice: di cosa parla la trama e perché vale la pena vederlo?`;
      ask(first);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready]);

  const ask = useCallback(
    async (question: string) => {
      const q = question.trim();
      if (!q || streaming) return;
      Haptics.selectionAsync();
      setError(null);
      setInput("");
      const history = messages;
      setMessages((m) => [...m, { role: "user", content: q }]);
      setStreaming(true);
      setStreamText("");
      try {
        const full = await chat(q, context, history, (partial) => {
          setStreamText(partial);
          scrollRef.current?.scrollToEnd({ animated: true });
        });
        setMessages((m) => [...m, { role: "assistant", content: full }]);
      } catch {
        setError("Generazione interrotta. Riprova.");
      } finally {
        setStreaming(false);
        setStreamText("");
        scrollRef.current?.scrollToEnd({ animated: true });
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [streaming, messages, context.text, context.title, context.source, mode]
  );

  const stop = async () => {
    Haptics.selectionAsync();
    await stopChat();
  };

  const quicks =
    mode === "news"
      ? [
          {
            label: "Spiegami questa notizia",
            q: `Spiegami in parole semplici questa notizia di cinema: "${context.title ?? ""}". Cosa significa e perché è importante?`,
          },
          {
            label: "Perché è importante?",
            q: `Perché questa notizia è importante per il mondo del cinema: "${context.title ?? ""}"? Spiegami il contesto.`,
          },
          {
            label: "Dammi altri dettagli",
            q: `Dammi altri dettagli e contesto su questa notizia di cinema: "${context.title ?? ""}".`,
          },
        ]
      : [
          {
            label: "Spiegami la trama",
            q: `Spiegami in parole semplici la trama del film "${context.title ?? ""}" senza spoiler importanti.`,
          },
          {
            label: "Che genere è?",
            q: `Che tipo di film è "${context.title ?? ""}"? A cosa o a quali film somiglia?`,
          },
          {
            label: "Me lo consigli?",
            q: `Considerando trama e genere, a chi consiglieresti il film "${context.title ?? ""}"? Spiega perché.`,
          },
        ];

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
          <Text style={styles.ctxLabel}>{mode === "news" ? "NOTIZIA" : "FILM"}</Text>
          <Text style={styles.ctxTitle} numberOfLines={2}>
            {context.title}
          </Text>
        </View>
      ) : null}

      {/* ---------- IN MANUTENZIONE: l'AI si sta preparando ---------- */}
      {maintenance ? (
        <View style={styles.maintWrap}>
          <Text style={{ fontSize: 48, marginBottom: 12 }}>🛠️</Text>
          <Text style={styles.maintTitle}>AI in manutenzione</Text>
          <Text style={styles.maintText}>
            {ai.phase === "downloading"
              ? `Sto scaricando il modello ${model.name} (${model.sizeGB.toFixed(1)} GB) sul telefono. La pagina si sbloccherà da sola appena finito.`
              : ai.phase === "assembling"
                ? "Download completato! Sto assemblando il file… (meno di un minuto)"
                : "Sto caricando l'AI in memoria. Attendi qualche istante…"}
          </Text>

          {(ai.phase === "downloading" || ai.phase === "assembling") && (
            <View style={styles.loadTrack}>
              <View
                style={[
                  styles.loadFill,
                  {
                    width: `${Math.max(3, Math.round(ai.progress * 100))}%`,
                    opacity: ai.phase === "assembling" ? 0.6 : 1,
                  },
                ]}
              />
            </View>
          )}
          {(ai.phase === "downloading" || ai.phase === "assembling") && (
            <Text style={styles.progressText}>
              {ai.phase === "downloading"
                ? `${Math.round(ai.progress * 100)}% · va avanti anche se esci dalla pagina`
                : `Assemblaggio ${Math.round(ai.progress * 100)}%`}
            </Text>
          )}
          {(ai.phase === "idle" || ai.phase === "loading") && (
            <ActivityIndicator color={theme.colors.accent} style={{ marginTop: 18 }} />
          )}

          <Text style={styles.maintHint}>
            🔒 Una sola volta: il modello resta sul telefono e l'AI funziona anche
            offline. Nessun dato lascia il tuo iPhone.
          </Text>

          {/* Riprova solo in caso di errore */}
          {ai.phase === "error" && (
            <Pressable onPress={retryAIBootstrap} style={styles.retryBtn}>
              <GlassView glassEffectStyle="clear" isInteractive style={styles.glassPill}>
                <Text style={styles.retryText}>↻ Riprova</Text>
              </GlassView>
            </Pressable>
          )}
        </View>
      ) : /* ---------- ERRORE (download/caricamento fallito) ---------- */
      ai.phase === "error" ? (
        <View style={styles.maintWrap}>
          <Text style={{ fontSize: 44, marginBottom: 12 }}>😵‍💫</Text>
          <Text style={styles.maintTitle}>AI non disponibile</Text>
          <Text style={styles.maintText}>{ai.error ?? "Preparazione non riuscita."}</Text>
          {!ai.error?.includes("development build") && (
            <Text style={styles.maintText}>
              Controlla la connessione e riprova: il download riprende da dove si
              era fermato.
            </Text>
          )}
          <Pressable onPress={retryAIBootstrap} style={styles.retryBtn}>
            <GlassView glassEffectStyle="clear" isInteractive style={styles.glassPill}>
              <Text style={styles.retryText}>↻ Riprova</Text>
            </GlassView>
          </Pressable>
        </View>
      ) : (
        /* ---------- PRONTA: chat ---------- */
        <KeyboardAvoidingView
          style={{ flex: 1 }}
          behavior={Platform.OS === "ios" ? "padding" : undefined}
          keyboardVerticalOffset={Platform.OS === "ios" ? 90 : 0}
        >
          <ScrollView
            ref={scrollRef}
            contentContainerStyle={styles.chat}
            onContentSizeChange={() => scrollRef.current?.scrollToEnd({ animated: false })}
          >
            {messages.length === 0 && !streaming && (
              <View style={styles.welcome}>
                <Text style={styles.welcomeText}>
                  Chiedimi quello che vuoi su{" "}
                  <Text style={styles.welcomeBold}>
                    {context.title ?? "questo contenuto"}
                  </Text>
                  . Ti spiego tutto in parole semplici. ✨
                </Text>
              </View>
            )}

            {messages.map((m, i) => (
              <View
                key={i}
                style={[styles.bubble, m.role === "user" ? styles.bubbleUser : styles.bubbleAI]}
              >
                <Text style={m.role === "user" ? styles.bubbleUserText : styles.bubbleAIText}>
                  {m.content}
                </Text>
              </View>
            ))}

            {streaming && (
              <View style={[styles.bubble, styles.bubbleAI]}>
                {streamText.length === 0 ? (
                  <View style={s.row}>
                    <ActivityIndicator color={theme.colors.accent} size="small" />
                    <Text style={styles.thinking}> sto pensando…</Text>
                  </View>
                ) : (
                  <Text style={styles.bubbleAIText}>{streamText}</Text>
                )}
              </View>
            )}

            {error ? <Text style={styles.errText}>{error}</Text> : null}

            {/* Suggerimenti rapidi */}
            {messages.length === 0 && !streaming && (
              <View style={styles.quickWrap}>
                {quicks.map((q) => (
                  <Pressable
                    key={q.label}
                    onPress={() => ask(q.q)}
                    style={({ pressed }) => [styles.quickChip, pressed && { opacity: 0.7 }]}
                  >
                    <GlassView glassEffectStyle="clear" isInteractive style={styles.glassPill}>
                      <Text style={styles.quickText}>✨ {q.label}</Text>
                    </GlassView>
                  </Pressable>
                ))}
              </View>
            )}
          </ScrollView>

          {/* Barra input */}
          <View style={styles.inputBar}>
            {streaming ? (
              <Pressable onPress={stop} style={styles.stopBtn}>
                <GlassView
                  glassEffectStyle="clear"
                  isInteractive
                  tintColor={theme.colors.danger}
                  style={styles.glassPill}
                >
                  <Text style={styles.stopText}>■ Interrompi</Text>
                </GlassView>
              </Pressable>
            ) : (
              <>
                <View style={s.grow}>
                  <TextInputBar value={input} onChange={setInput} onSend={() => ask(input)} />
                </View>
                <Pressable
                  onPress={() => ask(input)}
                  disabled={input.trim().length === 0}
                  style={({ pressed }) => [
                    styles.sendBtn,
                    input.trim().length === 0 && { opacity: 0.35 },
                    pressed && { opacity: 0.7 },
                  ]}
                >
                  <GlassView
                    glassEffectStyle="regular"
                    tintColor={theme.colors.accent}
                    isInteractive
                    style={styles.sendGlass}
                  >
                    <Text style={styles.sendText}>↑</Text>
                  </GlassView>
                </Pressable>
              </>
            )}
          </View>
        </KeyboardAvoidingView>
      )}
    </View>
  );
}

/** Campo input locale (riusa lo stile dell'app). */
function TextInputBar({
  value,
  onChange,
  onSend,
}: {
  value: string;
  onChange: (t: string) => void;
  onSend: () => void;
}) {
  return (
    <View style={styles.inputWrap}>
      <RNTextInput
        value={value}
        onChangeText={onChange}
        onSubmitEditing={onSend}
        placeholder="Chiedi all'AI…"
        placeholderTextColor={theme.colors.textDim}
        autoCapitalize="sentences"
        multiline
        style={styles.input}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  headerTitle: { color: theme.colors.text, fontSize: 16, fontWeight: "700" },
  ctxBanner: {
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: theme.colors.border,
    backgroundColor: theme.colors.surface,
  },
  ctxLabel: {
    color: theme.colors.accent,
    fontSize: 10,
    fontWeight: "800",
    letterSpacing: 1,
  },
  ctxTitle: { color: theme.colors.text, fontSize: 14, fontWeight: "700", marginTop: 3 },

  /* Manutenzione */
  maintWrap: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 32,
  },
  maintTitle: { color: theme.colors.text, fontSize: 20, fontWeight: "800", marginBottom: 8 },
  maintText: {
    color: theme.colors.textDim,
    fontSize: 14,
    lineHeight: 21,
    textAlign: "center",
  },
  maintHint: {
    color: theme.colors.textDim,
    fontSize: 11,
    lineHeight: 16,
    textAlign: "center",
    marginTop: 22,
    maxWidth: 300,
  },
  progressText: {
    color: theme.colors.textDim,
    fontSize: 12,
    fontWeight: "700",
    marginTop: 8,
  },
  loadTrack: {
    alignSelf: "stretch",
    height: 6,
    borderRadius: 3,
    backgroundColor: theme.colors.surfaceAlt,
    marginTop: 18,
    overflow: "hidden",
  },
  loadFill: { height: 6, backgroundColor: theme.colors.accent, borderRadius: 3 },
  retryBtn: {
    marginTop: 18,
    borderRadius: theme.radius.sm,
  },
  retryText: { color: theme.colors.accent, fontWeight: "800", fontSize: 14, paddingHorizontal: 22, paddingVertical: 11 },

  /* Chat */
  chat: { padding: 16, paddingBottom: 24 },
  welcome: { marginBottom: 14 },
  welcomeText: { color: theme.colors.textDim, fontSize: 14, lineHeight: 21 },
  welcomeBold: { color: theme.colors.text, fontWeight: "800" },
  bubble: {
    maxWidth: "88%",
    borderRadius: theme.radius.md,
    paddingVertical: 10,
    paddingHorizontal: 14,
    marginBottom: 10,
  },
  bubbleUser: {
    alignSelf: "flex-end",
    backgroundColor: theme.colors.accent,
    borderBottomRightRadius: 4,
  },
  bubbleAI: {
    alignSelf: "flex-start",
    backgroundColor: theme.colors.surface,
    borderWidth: 1,
    borderColor: theme.colors.border,
    borderBottomLeftRadius: 4,
  },
  bubbleUserText: { color: theme.colors.bg, fontSize: 15, lineHeight: 21, fontWeight: "600" },
  bubbleAIText: { color: theme.colors.text, fontSize: 15, lineHeight: 22 },
  thinking: { color: theme.colors.textDim, fontSize: 14 },
  errText: { color: theme.colors.warn, fontSize: 12, marginBottom: 10 },

  quickWrap: { flexDirection: "row", flexWrap: "wrap", marginTop: 4 },
  quickChip: {
    marginRight: 8,
    marginBottom: 8,
  },
  glassPill: {
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: "rgba(255,255,255,0.14)",
    ...Platform.select({
      ios: {},
      default: { backgroundColor: "rgba(255,255,255,0.10)" },
    }),
  },
  quickText: { color: theme.colors.accent, fontSize: 13, fontWeight: "700", paddingHorizontal: 12, paddingVertical: 7 },

  /* Input */
  inputBar: {
    flexDirection: "row",
    alignItems: "flex-end",
    paddingHorizontal: 12,
    paddingTop: 8,
    paddingBottom: 10,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: theme.colors.border,
    backgroundColor: theme.colors.bg,
  },
  inputWrap: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: theme.colors.surfaceAlt,
    borderRadius: theme.radius.sm,
    borderWidth: 1,
    borderColor: theme.colors.border,
    paddingHorizontal: 12,
    minHeight: 42,
  },
  input: {
    flex: 1,
    color: theme.colors.text,
    fontSize: 15,
    paddingVertical: 10,
    maxHeight: 100,
  },
  sendBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    marginLeft: 8,
  },
  sendGlass: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: "center" as const,
    justifyContent: "center" as const,
    ...Platform.select({
      ios: {},
      default: { backgroundColor: theme.colors.accent },
    }),
  },
  sendText: { color: theme.colors.bg, fontSize: 18, fontWeight: "900" },
  stopBtn: {
    flex: 1,
    borderRadius: theme.radius.sm,
    alignItems: "center" as const,
  },
  stopText: { color: theme.colors.danger, fontWeight: "800", fontSize: 14, paddingHorizontal: 22, paddingVertical: 12 },
});
