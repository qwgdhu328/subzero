import React, { useState } from "react";
import {
  Alert,
  Linking,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  View,
} from "react-native";
import * as Haptics from "expo-haptics";
import { useRouter } from "expo-router";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { theme, fonts } from "../../src/theme";
import { styles as s } from "../../src/theme";
import { useStoreContext } from "../../src/storage/StoreContext";
import { DEFAULT_SOURCES, BUILT_IN_TMDB_API_KEY } from "../../src/storage/store";
import { ensureNotificationPermission } from "../../src/logic/liveNews";
import { NewsSource } from "../../src/models/types";
import { GlassCard, GlassButton, TextInput, Field } from "../../src/components/ui";
import { AISettingsCard } from "../../src/components/AIModelManager";

export default function SettingsScreen() {
  const { settings, update } = useStoreContext();
  const insets = useSafeAreaInsets();
  const router = useRouter();

  const [keyDraft, setKeyDraft] = useState(
    settings.tmdbApiKey === BUILT_IN_TMDB_API_KEY ? "" : (settings.tmdbApiKey ?? "")
  );
  const [newName, setNewName] = useState("");
  const [newUrl, setNewUrl] = useState("");

  const saveKey = () => {
    const trimmed = keyDraft.trim();
    // Campo vuoto → torna alla chiave inclusa (nessuna modalità "senza chiave")
    update({ tmdbApiKey: trimmed.length > 0 ? trimmed : BUILT_IN_TMDB_API_KEY });
    if (trimmed.length === 0) setKeyDraft("");
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  };

  const toggleDefault = (key: string, value: boolean) => {
    Haptics.selectionAsync();
    const disabled = new Set(settings.disabledSources);
    if (value) disabled.delete(key);
    else disabled.add(key);
    update({ disabledSources: [...disabled] });
  };

  const addCustom = () => {
    const name = newName.trim();
    const url = newUrl.trim();
    if (!name || !/^https?:\/\/.+/i.test(url)) {
      Alert.alert("Dati mancanti", "Inserisci un nome e un URL valido (https://…).");
      return;
    }
    const src: NewsSource = { key: `custom_${Date.now().toString(36)}`, name, url, enabled: true };
    update({ customSources: [...settings.customSources, src] });
    setNewName("");
    setNewUrl("");
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  };

  const removeCustom = (key: string) => {
    update({ customSources: settings.customSources.filter((x) => x.key !== key) });
  };

  return (
    <ScrollView style={s.screen} contentContainerStyle={{ padding: 16, paddingTop: 16 + insets.top, paddingBottom: 40 }}>
      {/* Masthead coerente con le altre tab */}
      <Text style={s.eyebrow}>CineFlash · Le tue preferenze</Text>
      <Text style={styles.masthead}>Impostazioni</Text>

      {/* TMDB */}
      <GlassCard style={{ marginTop: 16 }}>
        <Text style={s.sectionTitle}>TMDB</Text>
        <Text style={styles.dim}>
          L'app include già una chiave TMDB pronta all'uso: la tab Film mostra
          subito “Ora al cinema”, “In uscita” e “Popolari” con voti e trailer.
          Se preferisci, puoi usare la tua chiave gratuita ({""}
          <Text
            style={styles.link}
            onPress={() => {
              Linking.openURL("https://www.themoviedb.org/settings/api").catch(() => {});
            }}
          >
            themoviedb.org
          </Text>
          ) incollandola qui sotto: accetta sia la chiave v3 sia il Read Access
          Token v4.
        </Text>
        <View style={{ height: 10 }} />
        <Field label="Chiave API TMDB personalizzata (opzionale)">
          <TextInput
            value={keyDraft}
            onChangeText={setKeyDraft}
            placeholder="Chiave inclusa in uso — incolla qui la tua"
            autoCapitalize="none"
          />
        </Field>
        <GlassButton label="Usa la mia chiave" onPress={saveKey} />
        {settings.tmdbApiKey && settings.tmdbApiKey !== BUILT_IN_TMDB_API_KEY ? (
          <>
            <Text style={styles.okText}>✓ In uso la tua chiave personalizzata.</Text>
            <GlassButton
              label="↺ Ripristina la chiave inclusa"
              onPress={() => {
                update({ tmdbApiKey: BUILT_IN_TMDB_API_KEY });
              setKeyDraft("");
              Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
              }}
            />
          </>
        ) : (
          <Text style={styles.okText}>✓ In uso la chiave inclusa: tutto già configurato.</Text>
        )}
      </GlassCard>

      {/* AI locale */}
      <GlassCard style={{ marginTop: 12 }}>
        <AISettingsCard />
      </GlassCard>

      {/* Notifiche */}
      <GlassCard style={{ marginTop: 12 }}>
        <Text style={s.sectionTitle}>Notifiche</Text>
        <View style={[s.row, styles.sourceRow]}>
          <View style={s.grow}>
            <Text style={styles.sourceName}>Avvisami subito</Text>
            <Text style={styles.dim}>
              Notifica locale quando arrivano nuove notizie o si aprono
              prevendite. L'app controlla i feed ogni minuto in primo piano e
              periodicamente in background.
            </Text>
          </View>
          <Switch
            value={settings.notifyEnabled !== false}
            onValueChange={(v) => {
              Haptics.selectionAsync();
              update({ notifyEnabled: v });
              if (v) ensureNotificationPermission().catch(() => {});
            }}
            trackColor={{ true: theme.colors.accentDark, false: theme.colors.surfaceAlt }}
            thumbColor={
              settings.notifyEnabled !== false ? theme.colors.accent : theme.colors.textDim
            }
            ios_backgroundColor={theme.colors.surfaceAlt}
          />
        </View>
      </GlassCard>

      {/* Sorgenti predefinite */}
      <GlassCard style={{ marginTop: 12 }}>
        <Text style={s.sectionTitle}>Fonti notizie</Text>
        {DEFAULT_SOURCES.map((src) => {
          const enabled = !settings.disabledSources.includes(src.key);
          return (
            <View key={src.key} style={[s.row, styles.sourceRow]}>
              <View style={s.grow}>
                <Text style={styles.sourceName}>{src.name}</Text>
                <Text style={styles.sourceUrl} numberOfLines={1}>
                  {src.url}
                </Text>
              </View>
              <Switch
                value={enabled}
                onValueChange={(v) => toggleDefault(src.key, v)}
                trackColor={{ true: theme.colors.accentDark, false: theme.colors.surfaceAlt }}
                thumbColor={enabled ? theme.colors.accent : theme.colors.textDim}
                ios_backgroundColor={theme.colors.surfaceAlt}
              />
            </View>
          );
        })}

        {/* Sorgenti custom */}
        {settings.customSources.map((src) => (
          <View key={src.key} style={[s.row, styles.sourceRow]}>
            <View style={s.grow}>
              <Text style={styles.sourceName}>{src.name}</Text>
              <Text style={styles.sourceUrl} numberOfLines={1}>
                {src.url}
              </Text>
            </View>
            <Pressable onPress={() => removeCustom(src.key)} hitSlop={8}>
              <Text style={{ color: theme.colors.danger, fontWeight: "800" }}>🗑</Text>
            </Pressable>
          </View>
        ))}
      </GlassCard>

      {/* Aggiungi fonte */}
      <GlassCard style={{ marginTop: 12 }}>
        <Text style={s.sectionTitle}>Aggiungi una fonte RSS</Text>
        <Field label="Nome">
          <TextInput value={newName} onChangeText={setNewName} placeholder="es. Il Mio Blog di Cinema" />
        </Field>
        <Field label="URL del feed RSS">
          <TextInput
            value={newUrl}
            onChangeText={setNewUrl}
            placeholder="https://esempio.it/feed"
            autoCapitalize="none"
          />
        </Field>
        <GlassButton label="＋ Aggiungi fonte" onPress={addCustom} />
      </GlassCard>

      {/* Privacy */}
      <GlassCard style={{ marginTop: 12 }}>
        <Text style={s.sectionTitle}>Privacy e dati</Text>
        <Text style={styles.dim}>
          Nessun account, nessun analytics, nessun tracker: le tue liste e le
          tue impostazioni restano solo sul tuo dispositivo. L'AI gira
          interamente sul telefono.
        </Text>
        <GlassButton
          label="Leggi l'informativa privacy"
          onPress={() => {
            Haptics.selectionAsync();
            router.push("/privacy");
          }}
        />
      </GlassCard>

      
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  masthead: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 34,
    fontWeight: "700",
    letterSpacing: -0.5,
    lineHeight: 40,
    marginTop: 6,
    marginBottom: 4,
  },
  dim: { color: theme.colors.textDim, fontSize: 13, lineHeight: 19 },
  link: { color: theme.colors.accent, fontWeight: "700" },
  okText: { color: theme.colors.ok, fontSize: 12, fontWeight: "700", marginTop: 8 },
  warnText: { color: theme.colors.warn, fontSize: 12, fontWeight: "700", marginTop: 8 },
  sourceRow: {
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: theme.colors.border,
  },
  sourceName: { color: theme.colors.text, fontSize: 15, fontWeight: "700" },
  sourceUrl: { color: theme.colors.textDim, fontSize: 11, marginTop: 2 },
  foot: {
    color: theme.colors.textDim,
    fontSize: 11,
    textAlign: "center",
    marginTop: 24,
  },
});
