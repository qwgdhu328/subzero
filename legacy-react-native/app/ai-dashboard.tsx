import React, { useEffect, useState } from "react";
import {
  ActivityIndicator,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { Stack, useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { theme, fonts } from "../src/theme";
import { styles as s } from "../src/theme";
import { Poster } from "../src/components/ui";
import { Badge, GlassButton, GlassCard, EmptyState } from "../src/components/ui";
import {
  CurationState,
  CurationProposal,
  EMPTY_CURATION,
  generateProposal,
  loadCuration,
  saveCuration,
} from "../src/logic/movieCuration";
import { loadMoviesCache } from "../src/storage/store";
import { Movie } from "../src/models/types";
import { fmtReleaseDate, posterUrl } from "../src/logic/tmdb";

/**
 * Dashboard della Redazione AI del catalogo film.
 *
 * Genera una proposta (promuovi / nascondi) valutando voto, data di uscita
 * e completezza della trama, la mostra con poster e motivazione, e la
 * applica su richiesta: da quel momento Film e Prevendite rispettano le
 * decisioni della redazione. Tutto resta sul dispositivo.
 */
export default function AIDashboardScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();

  const [state, setState] = useState<CurationState>(EMPTY_CURATION);
  const [catalog, setCatalog] = useState<{
    now: Movie[];
    upcoming: Movie[];
    popular: Movie[];
  } | null>(null);
  const [proposal, setProposal] = useState<CurationProposal | null>(null);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);

  useEffect(() => {
    (async () => {
      const [c, cache] = await Promise.all([loadCuration(), loadMoviesCache()]);
      setState(c);
      if (cache) {
        setCatalog({
          now: cache.nowPlaying,
          upcoming: cache.upcoming,
          popular: cache.popular,
        });
      }
      setLoading(false);
    })();
  }, []);

  const runProposal = () => {
    if (!catalog) return;
    setGenerating(true);
    Haptics.selectionAsync();
    // Piccola attesa per dare il senso di "la redazione sta valutando"
    setTimeout(() => {
      const p = generateProposal(catalog.now, catalog.upcoming, catalog.popular);
      setProposal(p);
      setGenerating(false);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    }, 700);
  };

  const apply = async () => {
    if (!proposal) return;
    const next: CurationState = {
      promoted: proposal.promote.map((m) => String(m.id)),
      hidden: proposal.hide.map((m) => String(m.id)),
      generatedAt: new Date().toISOString(),
      note: proposal.reasoning,
    };
    await saveCuration(next);
    setState(next);
    setProposal(null);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  };

  const reset = async () => {
    await saveCuration(EMPTY_CURATION);
    setState(EMPTY_CURATION);
    setProposal(null);
    Haptics.selectionAsync();
  };

  /** Rimuove un singolo film dalle liste della curation attiva. */
  const clearEntry = async (id: string) => {
    const next: CurationState = {
      ...state,
      promoted: state.promoted.filter((x) => x !== id),
      hidden: state.hidden.filter((x) => x !== id),
    };
    await saveCuration(next);
    setState(next);
    Haptics.selectionAsync();
  };

  const byId = (id: string): Movie | null => {
    if (!catalog) return null;
    return (
      catalog.now.find((m) => String(m.id) === id) ??
      catalog.upcoming.find((m) => String(m.id) === id) ??
      catalog.popular.find((m) => String(m.id) === id) ??
      null
    );
  };

  return (
    <View style={s.screen}>
      <Stack.Screen options={{ headerShown: false }} />
      <ScrollView
        contentContainerStyle={[
          styles.wrap,
          { paddingTop: 14 + insets.top, paddingBottom: 40 + insets.bottom },
        ]}
      >
        <DashboardHeader onBack={() => router.back()} />

        <Text style={s.eyebrow}>CineFlash · Redazione AI</Text>
        <Text style={styles.masthead}>Dashboard catalogo</Text>
        <Text style={styles.lead}>
          La redazione AI valuta voto, data di uscita e completezza delle
          informazioni e decide quali film devono restare ben visibili e quali
          togliere. Le decisioni si applicano alle pagine Film e Prevendite.
        </Text>

        {loading ? (
          <ActivityIndicator color={theme.colors.accent} style={{ padding: 40 }} />
        ) : !catalog ? (
          <EmptyState
            icon="🎬"
            title="Catalogo non ancora caricato"
            subtitle="Apri prima la pagina Film: appena c'è la cache del catalogo la dashboard diventa attiva."
          />
        ) : (
          <>
            {/* Stato attuale */}
            <GlassCard style={{ marginTop: 16 }}>
              <Text style={s.sectionTitle}>Decisioni attive</Text>
              {state.promoted.length === 0 && state.hidden.length === 0 ? (
                <Text style={styles.dim}>
                  Nessuna decisione attiva: il catalogo segue l'ordine standard
                  di TMDB.
                </Text>
              ) : (
                <>
                  {state.promoted.length > 0 ? (
                    <Text style={styles.stateLine}>
                      ⬆ {state.promoted.length} film promossi · ⬇{" "}
                      {state.hidden.length} nascosti
                    </Text>
                  ) : (
                    <Text style={styles.stateLine}>
                      ⬇ {state.hidden.length} film nascosti
                    </Text>
                  )}
                  {state.generatedAt ? (
                    <Text style={styles.stateMeta}>
                      Applicate il{" "}
                      {new Date(state.generatedAt).toLocaleDateString("it-IT", {
                        day: "numeric",
                        month: "long",
                        year: "numeric",
                      })}
                    </Text>
                  ) : null}
                  {state.note ? (
                    <Text style={styles.stateNote}>{state.note}</Text>
                  ) : null}
                  <View style={styles.decisionList}>
                    {[...state.promoted, ...state.hidden].map((id) => {
                      const m = byId(id);
                      if (!m) return null;
                      const promoted = state.promoted.includes(id);
                      return (
                        <View key={id} style={styles.decisionRow}>
                          <Poster
                            uri={posterUrl(m.posterPath, "w342")}
                            style={styles.decisionPoster}
                          />
                          <View style={s.grow}>
                            <Text style={styles.decisionTitle} numberOfLines={1}>
                              {m.title}
                            </Text>
                            <View style={s.row}>
                              <Badge
                                label={promoted ? "⬆ PROMOSSO" : "⬇ NASCOSTO"}
                                tone={promoted ? "ok" : "danger"}
                              />
                              <Text style={styles.decisionDate}>
                                {"  "}
                                {fmtReleaseDate(m.releaseDate)}
                              </Text>
                            </View>
                          </View>
                          <PressableRemove onPress={() => clearEntry(id)} />
                        </View>
                      );
                    })}
                  </View>
                </>
              )}
              {state.promoted.length + state.hidden.length > 0 ? (
                <GlassButton label="↺ Ripristina catalogo standard" onPress={reset} />
              ) : null}
            </GlassCard>

            {/* Genera proposta */}
            <GlassCard style={{ marginTop: 12 }}>
              <Text style={s.sectionTitle}>Nuova valutazione</Text>
              <Text style={styles.dim}>
                Genera una proposta di redazione sul catalogo attuale: vedrai
                promo ed esclusioni con motivazione, prima di applicarle.
              </Text>
              <GlassButton
                label={generating ? "… Valuto il catalogo" : "✨ Genera proposta"}
                onPress={runProposal}
              />
              {generating ? (
                <ActivityIndicator
                  color={theme.colors.accent}
                  style={{ marginTop: 12 }}
                />
              ) : null}

              {proposal ? (
                <View style={{ marginTop: 14 }}>
                  <Text style={styles.proposalReason}>{proposal.reasoning}</Text>

                  {proposal.promote.length > 0 ? (
                    <>
                      <Text style={styles.proposalHead}>
                        ⬆ Da promuovere ({proposal.promote.length})
                      </Text>
                      {proposal.promote.slice(0, 6).map((m) => (
                        <ProposalRow key={`p${m.id}`} movie={m} tone="ok" />
                      ))}
                    </>
                  ) : null}

                  {proposal.hide.length > 0 ? (
                    <>
                      <Text style={styles.proposalHead}>
                        ⬇ Da togliere ({proposal.hide.length})
                      </Text>
                      {proposal.hide.slice(0, 6).map((m) => (
                        <ProposalRow key={`h${m.id}`} movie={m} tone="danger" />
                      ))}
                    </>
                  ) : null}

                  <GlassButton label="✓ Applica alla redazione" filled onPress={apply} />
                </View>
              ) : null}
            </GlassCard>
          </>
        )}
      </ScrollView>
    </View>
  );
}

function DashboardHeader({ onBack }: { onBack: () => void }) {
  return (
    <View style={styles.headerRow}>
      <PressableBack onPress={onBack} />
    </View>
  );
}

import { Pressable } from "react-native";

function PressableBack({ onPress }: { onPress: () => void }) {
  return (
    <Pressable onPress={onPress} hitSlop={10}>
      <View style={styles.backBtn}>
        <Text style={styles.backText}>‹</Text>
      </View>
    </Pressable>
  );
}

function PressableRemove({ onPress }: { onPress: () => void }) {
  return (
    <Pressable onPress={onPress} hitSlop={8} style={styles.removeChip}>
      <Text style={styles.removeChipText}>Togli</Text>
    </Pressable>
  );
}

function ProposalRow({ movie, tone }: { movie: Movie; tone: "ok" | "danger" }) {
  return (
    <View style={styles.decisionRow}>
      <Poster uri={posterUrl(movie.posterPath, "w342")} style={styles.decisionPoster} />
      <View style={s.grow}>
        <Text style={styles.decisionTitle} numberOfLines={1}>
          {movie.title}
        </Text>
        <View style={s.row}>
          <Badge
            label={tone === "ok" ? "⬆ PROMUOVI" : "⬇ TOGLI"}
            tone={tone}
          />
          <Text style={styles.decisionDate}>
            {"  "}
            {fmtReleaseDate(movie.releaseDate)}
          </Text>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { paddingHorizontal: 16 },
  headerRow: { marginBottom: 10 },
  backBtn: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: "center",
    justifyContent: "center",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    backgroundColor: theme.colors.surfaceAlt,
  },
  backText: {
    color: theme.colors.text,
    fontSize: 24,
    fontWeight: "700",
    marginTop: -2,
  },
  masthead: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 30,
    fontWeight: "700",
    letterSpacing: -0.5,
    lineHeight: 36,
    marginTop: 4,
  },
  lead: {
    color: theme.colors.textDim,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 8,
  },
  dim: { color: theme.colors.textDim, fontSize: 13, lineHeight: 19 },
  stateLine: {
    color: theme.colors.text,
    fontSize: 14,
    fontWeight: "800",
    marginBottom: 4,
  },
  stateMeta: { color: theme.colors.textDim, fontSize: 11, marginBottom: 4 },
  stateNote: {
    color: theme.colors.textDim,
    fontSize: 12,
    lineHeight: 17,
    marginBottom: 10,
  },
  decisionList: { marginTop: 10, gap: 10 },
  decisionRow: { flexDirection: "row", alignItems: "center", gap: 12 },
  decisionPoster: { width: 44, height: 66, borderRadius: theme.radius.xs },
  decisionTitle: {
    color: theme.colors.text,
    fontSize: 14,
    fontWeight: "700",
    marginBottom: 3,
  },
  decisionDate: { color: theme.colors.textDim, fontSize: 11 },
  removeChip: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.danger + "55",
    backgroundColor: theme.colors.dangerBg,
  },
  removeChipText: { color: theme.colors.danger, fontSize: 11, fontWeight: "700" },
  proposalReason: {
    color: theme.colors.text,
    fontSize: 13,
    lineHeight: 19,
    marginBottom: 12,
  },
  proposalHead: {
    color: theme.colors.textDim,
    fontSize: 11,
    fontWeight: "800",
    letterSpacing: 1.5,
    textTransform: "uppercase",
    marginTop: 10,
    marginBottom: 8,
  },
});
