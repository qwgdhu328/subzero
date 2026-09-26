import React from "react";
import {
  Alert,
  ScrollView,
  Share,
  StyleSheet,
  Switch,
  Text,
  View,
} from "react-native";
import Constants from "expo-constants";
import * as Haptics from "expo-haptics";
import { Stack, useRouter } from "expo-router";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { theme } from "../src/theme";
import { styles as s } from "../src/theme";
import { useStoreContext } from "../src/storage/StoreContext";
import { ensureNotificationPermission } from "../src/logic/liveNews";
import { GlassCard, GlassButton } from "../src/components/ui";
import { ScreenHeader } from "../src/components/ScreenHeader";

export default function SettingsScreen() {
  const { settings, watchlist, savedNews, update } = useStoreContext();
  const insets = useSafeAreaInsets();
  const router = useRouter();

  /* Versione per il footer (fallback "1.0" se expo-constants non la espone) */
  const versionString =
    (Constants.expoConfig?.version as string | undefined) ?? "1.0";

  return (
    <ScrollView style={s.screen} contentContainerStyle={{ padding: 16, paddingTop: 16 + insets.top, paddingBottom: 40 }}>
      <Stack.Screen
        options={{
          headerShown: true,
          headerTitle: "Impostazioni",
          headerTitleStyle: styles.headerTitle,
          headerTintColor: theme.colors.accent,
          headerShadowVisible: false,
          headerBackTitle: "Indietro",
          headerStyle: { backgroundColor: theme.colors.bg },
        }}
      />

      {/* Le sezioni (Dashboard AI, Notifiche, Permessi…) restano invariate */}

      {/* Dashboard redazione AI: cura il catalogo film */}
      <GlassCard style={{ marginTop: 12 }}>
        <Text style={s.sectionTitle}>Dashboard AI</Text>
        <Text style={styles.dim}>
          La redazione AI valuta il catalogo e decide quali film promuovere e
          quali togliere da Film e Prevendite. Puoi generare la proposta,
          guardarla e applicarla quando vuoi.
        </Text>
        <GlassButton
          label="✨ Apri la dashboard del catalogo"
          onPress={() => {
            Haptics.selectionAsync();
            router.push("/ai-dashboard");
          }}
        />
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

      {/* Notizie: come funziona la redazione AI */}
      <GlassCard style={{ marginTop: 12 }}>
        <Text style={s.sectionTitle}>Notizie</Text>
        <Text style={styles.dim}>
          Le notizie di cinema vengono raccolte dalle principali testate
          italiane e riscritte dalla redazione AI di CineFlash in articoli
          chiari, con le immagini originali. La fonte resta sempre indicata
          nell'articolo.
        </Text>
      </GlassCard>



      {/* Rivivi l'intro cinematografica */}
      <GlassCard style={{ marginTop: 12 }}>
        <Text style={s.sectionTitle}>L'esperienza</Text>
        <Text style={styles.dim}>
          L'intro al primo avvio racconta come funziona CineFlash: puoi
          rivederla quando vuoi, magari per farla scoprire a un amico. 🍿
        </Text>
        <GlassButton
          label="🎬 Rivedi l'intro"
          onPress={() => {
            Haptics.selectionAsync();
            update({ onboarded: false });
            router.replace("/onboarding");
          }}
        />
      </GlassCard>

      {/* Centro permessi: trasparenza su notifiche, fototeca e posizione */}
      <GlassCard style={{ marginTop: 12 }}>
        <Text style={s.sectionTitle}>Permessi</Text>
        <Text style={styles.dim}>
          Notifiche, fototeca e posizione: cosa l'app usa e perché, con la
          possibilità di attivarli o revocarli quando vuoi.
        </Text>
        <GlassButton
          label="🔐 Centro permessi"
          onPress={() => {
            Haptics.selectionAsync();
            router.push("/permissions");
          }}
        />
      </GlassCard>

      {/* Privacy */}
      <GlassCard style={{ marginTop: 12 }}>
        <Text style={s.sectionTitle}>Privacy e dati</Text>
        <Text style={styles.dim}>
          Nessun account, nessun analytics, nessun tracker: le tue liste e le
          tue impostazioni restano solo sul tuo dispositivo.
        </Text>
        <GlassButton
          label="Leggi l'informativa privacy"
          onPress={() => {
            Haptics.selectionAsync();
            router.push("/privacy");
          }}
        />
      </GlassCard>

      {/* Watchlist: panoramica + export */}
      <GlassCard style={{ marginTop: 12 }}>
        <Text style={s.sectionTitle}>I miei film ({watchlist.list.length})</Text>
        {watchlist.list.length === 0 ? (
          <Text style={styles.dim}>
            Aggiungi film alla watchlist dal Catalogo con la stella: compariranno qui.
          </Text>
        ) : (
          <>
            <Text style={styles.watchPreview} numberOfLines={3}>
              {watchlist.list.map((x) => x.title).join(" · ")}
            </Text>
            <GlassButton
              label="↗ Esporta / condividi la lista"
              onPress={async () => {
                Haptics.selectionAsync();
                try {
                  await Share.share({
                    message: `I miei film da vedere 🎬\n\n${watchlist.list
                      .map((x, i) => `${i + 1}. ${x.title}`)
                      .join("\n")}\n\n— condiviso da CineFlash`,
                  });
                } catch {}
              }}
            />
          </>
        )}
      </GlassCard>

      {/* Gestione dati: cancella salvati / watchlist */}
      <GlassCard style={{ marginTop: 12 }}>
        <Text style={s.sectionTitle}>Gestione dati</Text>
        <Text style={styles.dim}>
          Tutto ciò che vedi qui sotto vive solo su questo dispositivo: puoi
          svuotarlo quando vuoi senza toccare il resto dell'app.
        </Text>
        <View style={{ height: 10 }} />
        <GlassButton
          label={`🗑 Svuota notizie salvate (${savedNews.saved.length})`}
          onPress={() => {
            if (savedNews.saved.length === 0) return;
            Alert.alert("Svuotare le notizie salvate?", "L'azione non si può annullare.", [
              { text: "Annulla", style: "cancel" },
              {
                text: "Svuota",
                style: "destructive",
                onPress: () => {
                  savedNews.clear();
                  Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
                },
              },
            ]);
          }}
        />
        <GlassButton
          label={`🗑 Svuota watchlist (${watchlist.list.length})`}
          onPress={() => {
            if (watchlist.list.length === 0) return;
            Alert.alert("Svuotare la watchlist?", "L'azione non si può annullare.", [
              { text: "Annulla", style: "cancel" },
              {
                text: "Svuota",
                style: "destructive",
                onPress: () => {
                  watchlist.clear();
                  Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
                },
              },
            ]);
          }}
        />
      </GlassCard>

      <Text style={styles.foot}>
        CineFlash {versionString} · fatta per chi ama il cinema{" "}
        <Text
          style={styles.footLink}
          onPress={() => {
            Haptics.selectionAsync();
            router.push("/privacy");
          }}
        >
          Privacy
        </Text>
      </Text>

    </ScrollView>
  );
}

const styles = StyleSheet.create({
  headerTitle: { color: theme.colors.text, fontSize: 16, fontWeight: "700" },
  masthead: {
    color: theme.colors.text,
    fontSize: 34,
    fontWeight: "700",
    letterSpacing: -0.5,
    lineHeight: 40,
    marginTop: 6,
    marginBottom: 4,
  },
  dim: { color: theme.colors.textDim, fontSize: 13, lineHeight: 19 },
  watchPreview: { color: theme.colors.text, fontSize: 14, lineHeight: 20, marginBottom: 12 },
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
  footLink: { color: theme.colors.accent, fontWeight: "700" },
});
