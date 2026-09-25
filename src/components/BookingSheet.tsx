import React, { useCallback, useEffect, useState } from "react";
import {
  ActivityIndicator,
  FlatList,
  Linking,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { GlassView } from "expo-glass-effect";
import { theme, fonts } from "../theme";
import { styles as s } from "../theme";
import { Cinema, cinemaMovieUrl, fetchCinemasByCity, sortByDistance } from "../logic/cinemas";
import { loadLastCity, saveLastCity } from "../storage/collections";
import { ModalSheet, TextInput } from "./ui";

/** Città proposte per la scelta rapida. */
const CITY_SUGGESTIONS = [
  "Roma",
  "Milano",
  "Napoli",
  "Torino",
  "Firenze",
  "Bologna",
  "Verona",
  "Bari",
];

/**
 * Flusso di prenotazione premium (stile concierge):
 * 1. scelta città con chip eleganti;
 * 2. elenco cinema reali della città (OpenStreetMap);
 * 3. tocca un cinema → si apre il suo sito con il film selezionato.
 */
export function BookingSheet({
  movieTitle,
  onClose,
}: {
  movieTitle: string | null;
  onClose: () => void;
}) {
  const [city, setCity] = useState("");
  const [cinemas, setCinemas] = useState<Cinema[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchedCity, setSearchedCity] = useState("");
  /** Indicatore di step: 1 = città, 2 = cinema. */
  const [nearbyOn, setNearbyOn] = useState(false);

  const search = useCallback(async (name: string, opts?: { nearby?: boolean }) => {
    const c = name.trim();
    if (c.length < 2) return;
    setLoading(true);
    setError(null);
    setSearchedCity(c);
    saveLastCity(c).catch(() => {});
    try {
      let list = await fetchCinemasByCity(c);
      if (opts?.nearby) {
        setNearbyOn(true);
        list = await sortByDistance(list);
      }
      setCinemas(list);
    } catch {
      setError("Impossibile scaricare l'elenco cinema. Riprova.");
      setCinemas(null);
    } finally {
      setLoading(false);
    }
  }, []);

  const openCinema = useCallback(
    async (cinema: Cinema) => {
      const url = cinemaMovieUrl(cinema, movieTitle ?? "");
      try {
        await Linking.openURL(url);
      } catch {}
    },
    [movieTitle]
  );

  // Reset quando cambia il film (riapertura da zero)
  useEffect(() => {
    if (movieTitle != null) {
      setCity("");
      setCinemas(null);
      setError(null);
      setSearchedCity("");
    }
  }, [movieTitle]);

  const open = movieTitle != null;

  return (
    <ModalSheet visible={open} onClose={onClose} title={`Prenota · ${movieTitle ?? ""}`}>
      {/* STEP 1 — Scelta città */}
      {cinemas === null && (
        <View>
          <Text style={styles.stepLabel}>IN QUALE CITTÀ?</Text>
          <View style={[s.row, { gap: 8 }]}>
            <View style={s.grow}>
              <TextInput
                value={city}
                onChangeText={setCity}
                placeholder="es. Roma"
                autoCapitalize="words"
              />
            </View>
            <Pressable
              onPress={() => search(city)}
              disabled={loading || city.trim().length < 2}
            >
              <GlassView
                glassEffectStyle="regular"
                tintColor={theme.colors.accent}
                isInteractive={!loading && city.trim().length >= 2}
                style={styles.goBtn}
              >
                <Text style={styles.goText}>{loading ? "…" : "Cerca"}</Text>
              </GlassView>
            </Pressable>
          </View>

          <View style={styles.suggestWrap}>
            {CITY_SUGGESTIONS.map((c) => (
              <Pressable
                key={c}
                onPress={() => {
                  setCity(c);
                  search(c);
                }}
                style={styles.suggestChip}
              >
                <Text style={styles.suggestText}>{c}</Text>
              </Pressable>
            ))}
          </View>

          <Pressable
            onPress={() => {
              if (city.trim().length >= 2) search(city, { nearby: true });
            }}
            disabled={loading || city.trim().length < 2}
            style={styles.nearbyBtn}
          >
            <Text style={styles.nearbyText}>
              📍 Ordina i cinema per distanza da me
            </Text>
          </Pressable>

          {error ? <Text style={styles.error}>{error}</Text> : null}
        </View>
      )}

      {/* STEP 2 — Elenco cinema */}
      {cinemas !== null && (
        <View style={{ maxHeight: 430 }}>
          <View style={[s.row, styles.listHeader]}>
            <View style={s.grow}>
              <Text style={styles.listEyebrow}>CINEMA A</Text>
              <Text style={styles.listCity}>{searchedCity}</Text>
            </View>
            <Pressable
              onPress={() => {
                setCinemas(null);
                setCity("");
              }}
              hitSlop={8}
            >
              <Text style={styles.changeCity}>Cambia</Text>
            </Pressable>
          </View>

          {loading ? (
            <View style={styles.loadingWrap}>
              <ActivityIndicator color={theme.colors.accent} size="large" />
              <Text style={styles.loadingText}>
                {nearbyOn
                  ? "Cerco i cinema e misuro le distanze…"
                  : "Cerco i cinema della città…"}
              </Text>
            </View>
          ) : cinemas.length === 0 ? (
            <View style={styles.emptyWrap}>
              <Text style={{ fontSize: 34 }}>🍿</Text>
              <Text style={styles.emptyTitle}>Nessun cinema trovato</Text>
              <Text style={styles.emptySub}>
                Non risultano cinema a {searchedCity}: prova con la città più vicina.
              </Text>
            </View>
          ) : (
            <FlatList
              data={cinemas}
              keyExtractor={(c) => c.id}
              keyboardShouldPersistTaps="handled"
              renderItem={({ item }) => (
                <Pressable
                  onPress={() => openCinema(item)}
                  style={({ pressed }) => [styles.cinemaRow, pressed && { opacity: 0.7 }]}
                >
                  <View style={styles.cinemaBadge}>
                    <Text style={styles.cinemaBadgeText}>
                      {initials(item.name)}
                    </Text>
                  </View>
                  <View style={s.grow}>
                    <Text style={styles.cinemaName} numberOfLines={1}>
                      {item.name}
                    </Text>
                    <Text style={styles.cinemaAddr} numberOfLines={1}>
                      {item.distanceKm != null
                        ? `${item.distanceKm.toFixed(1)} km`
                        : item.address ?? ""}
                    </Text>
                  </View>
                  <Text style={styles.siteHint}>
                    {item.website ? "PRENOTA" : "CERCA"}
                  </Text>
                </Pressable>
              )}
            />
          )}
        </View>
      )}
    </ModalSheet>
  );
}

/** Iniziali del cinema per il badge (max 2 lettere). */
function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter((w) => /^[A-Za-zÀ-ÿ]/.test(w))
    .slice(0, 2)
    .map((w) => w[0].toUpperCase())
    .join("");
}

const styles = StyleSheet.create({
  stepLabel: {
    color: theme.colors.textDim,
    fontSize: 11,
    fontWeight: "800",
    textTransform: "uppercase",
    letterSpacing: 2,
    marginBottom: 8,
  },
  goBtn: {
    borderRadius: theme.radius.sm,
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 16,
    paddingVertical: 12,
    ...Platform.select({
      ios: {},
      default: { backgroundColor: "rgba(245,197,24,0.9)" },
    }),
  },
  goText: { color: theme.colors.bg, fontWeight: "800", fontSize: 14 },
  suggestWrap: {
    flexDirection: "row",
    flexWrap: "wrap",
    marginTop: 14,
  },
  suggestChip: {
    backgroundColor: "rgba(255,255,255,0.06)",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: "rgba(255,255,255,0.16)",
    borderRadius: 999,
    paddingHorizontal: 13,
    paddingVertical: 7,
    marginRight: 8,
    marginBottom: 8,
  },
  suggestText: { color: theme.colors.textDim, fontSize: 12, fontWeight: "600" },
  error: { color: theme.colors.warn, fontSize: 12, marginTop: 8 },
  nearbyBtn: {
    alignSelf: "flex-start",
    marginTop: 14,
    paddingVertical: 6,
  },
  nearbyText: {
    color: theme.colors.accent,
    fontSize: 12,
    fontWeight: "700",
  },
  listHeader: {
    justifyContent: "space-between",
    alignItems: "flex-end",
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: theme.colors.border,
    paddingBottom: 10,
    marginBottom: 4,
  },
  listEyebrow: {
    color: theme.colors.accent,
    fontSize: 9,
    fontWeight: "800",
    letterSpacing: 2.5,
  },
  listCity: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 22,
    fontWeight: "700",
    marginTop: 2,
  },
  changeCity: { color: theme.colors.accent, fontSize: 12, fontWeight: "700" },
  loadingWrap: { alignItems: "center", padding: 36 },
  loadingText: { color: theme.colors.textDim, fontSize: 13, marginTop: 10 },
  emptyWrap: { alignItems: "center", padding: 28 },
  emptyTitle: {
    color: theme.colors.text,
    fontSize: 15,
    fontWeight: "800",
    marginTop: 8,
  },
  emptySub: {
    color: theme.colors.textDim,
    fontSize: 12,
    textAlign: "center",
    marginTop: 4,
    lineHeight: 17,
  },
  cinemaRow: {
    flexDirection: "row",
    alignItems: "center",
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: theme.colors.border,
    gap: 12,
  },
  cinemaBadge: {
    width: 38,
    height: 38,
    borderRadius: 10,
    backgroundColor: theme.colors.surfaceAlt,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    alignItems: "center",
    justifyContent: "center",
  },
  cinemaBadgeText: {
    color: theme.colors.accent,
    fontSize: 13,
    fontWeight: "800",
    letterSpacing: 0.5,
  },
  cinemaName: { color: theme.colors.text, fontSize: 14, fontWeight: "700" },
  cinemaAddr: { color: theme.colors.textDim, fontSize: 11, marginTop: 1 },
  siteHint: {
    color: theme.colors.accent,
    fontSize: 10,
    fontWeight: "800",
    letterSpacing: 1.5,
  },
});
