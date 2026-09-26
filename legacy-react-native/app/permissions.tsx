import React, { useCallback, useEffect, useState } from "react";
import {
  ActivityIndicator,
  Linking,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  View,
} from "react-native";
import { useRouter, useFocusEffect } from "expo-router";
import * as Haptics from "expo-haptics";
import * as Notifications from "expo-notifications";
import * as MediaLibrary from "expo-media-library";
import * as Location from "expo-location";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { theme } from "../src/theme";
import { styles as s } from "../src/theme";
import { useStoreContext } from "../src/storage/StoreContext";
import { ScreenHeader } from "../src/components/ScreenHeader";
import { GlassCard, GlassButton } from "../src/components/ui";
import { ensureNotificationPermission } from "../src/logic/liveNews";

type PermStatus = "unknown" | "granted" | "denied" | "unavailable";

/** Lettura del permesso notifiche nello stesso linguaggio del centro. */
async function notifStatus(): Promise<PermStatus> {
  const cur = await Notifications.getPermissionsAsync();
  if (cur.granted) return "granted";
  if (cur.status === Notifications.PermissionStatus.UNDETERMINED) return "unknown";
  return "denied";
}

async function mediaStatus(): Promise<PermStatus> {
  const cur = await MediaLibrary.getPermissionsAsync();
  if (cur.granted) return "granted";
  if (cur.status === "undetermined") return "unknown";
  return "denied";
}

async function locationStatus(): Promise<PermStatus> {
  const cur = await Location.getForegroundPermissionsAsync();
  if (cur.granted) return "granted";
  if (cur.status === "undetermined") return "unknown";
  return "denied";
}

/**
 * Centro permessi: un solo luogo trasparente dove l'utente vede cosa l'app
 * usa (notifiche, fototeca, posizione), perché serve e può darglielo o
 * negarlo. Design coerente con le altre pagine: card vetro + righe chiare.
 */
export default function PermissionsScreen() {
  const { settings, update } = useStoreContext();
  const insets = useSafeAreaInsets();
  const router = useRouter();

  const [notif, setNotif] = useState<PermStatus>("unknown");
  const [media, setMedia] = useState<PermStatus>("unknown");
  const [loc, setLoc] = useState<PermStatus>("unknown");
  const [busy, setBusy] = useState(false);

  const reload = useCallback(() => {
    notifStatus().then(setNotif).catch(() => {});
    mediaStatus().then(setMedia).catch(() => {});
    locationStatus().then(setLoc).catch(() => {});
  }, []);

  useFocusEffect(
    useCallback(() => {
      reload();
    }, [reload])
  );

  // Se le notifiche vengono concesse in-system, rispecchia il toggle dell'app.
  useEffect(() => {
    if (notif === "granted" && settings.notifyEnabled === false) {
      update({ notifyEnabled: true });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [notif]);

  const askNotif = async () => {
    setBusy(true);
    const ok = await ensureNotificationPermission();
    setNotif(ok ? "granted" : "denied");
    setBusy(false);
  };

  const askMedia = async () => {
    setBusy(true);
    try {
      const { canAskAgain, status } = await MediaLibrary.requestPermissionsAsync();
      if (status === "granted") {
        setMedia("granted");
      } else if (!canAskAgain) {
        setMedia("denied");
        // Negrato permanentemente: solo Impostazioni di sistema può sbloccare.
      } else {
        await mediaStatus().then(setMedia);
      }
    } catch {
      setMedia("denied");
    }
    setBusy(false);
  };

  const askLocation = async () => {
    setBusy(true);
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      setLoc(status === "granted" ? "granted" : "denied");
    } catch {
      setLoc("denied");
    }
    setBusy(false);
  };

  const openOS = () => {
    Haptics.selectionAsync();
    if (Platform.OS === "ios") {
      Linking.openURL("app-settings:").catch(() => {});
    } else {
      Linking.openSettings().catch(() => {});
    }
  };

  const Row = ({
    icon,
    title,
    body,
    status,
    onAsk,
    toggleValue,
    onToggle,
  }: {
    icon: string;
    title: string;
    body: string;
    status: PermStatus;
    onAsk?: () => void;
    toggleValue?: boolean;
    onToggle?: (v: boolean) => void;
  }) => (
    <View style={[s.row, styles.row]}>
      <Text style={styles.rowIcon}>{icon}</Text>
      <View style={s.grow}>
        <View style={s.row}>
          <Text style={styles.rowTitle}>{title}</Text>
          {status === "granted" ? (
            <View style={[styles.stateChip, { backgroundColor: theme.colors.ok + "1A" }]}>
              <Text style={[styles.stateText, { color: theme.colors.ok }]}>ATTIVO</Text>
            </View>
          ) : status === "denied" ? (
            <View style={[styles.stateChip, { backgroundColor: theme.colors.danger + "1A" }]}>
              <Text style={[styles.stateText, { color: theme.colors.danger }]}>OFF</Text>
            </View>
          ) : (
            <View style={[styles.stateChip, { backgroundColor: theme.colors.accent + "1A" }]}>
              <Text style={[styles.stateText, { color: theme.colors.accent }]}>DA ATTIVARE</Text>
            </View>
          )}
        </View>
        <Text style={styles.rowBody}>{body}</Text>
        {onAsk && status !== "granted" ? (
          <Pressable onPress={onAsk} hitSlop={6} style={styles.askBtn}>
            <Text style={styles.askText}>
              {status === "denied" ? "Apri Impostazioni" : "Attiva ora"}
            </Text>
          </Pressable>
        ) : null}
        {onToggle ? (
          <Switch
            value={toggleValue}
            onValueChange={onToggle}
            trackColor={{ true: theme.colors.accentDark, false: theme.colors.surfaceAlt }}
            thumbColor={toggleValue ? theme.colors.accent : theme.colors.textDim}
            ios_backgroundColor={theme.colors.surfaceAlt}
          />
        ) : null}
      </View>
    </View>
  );

  return (
    <ScrollView
      style={s.screen}
      contentContainerStyle={{ padding: 16, paddingTop: 16 + insets.top, paddingBottom: 40 }}
    >
      <ScreenHeader
        eyebrow="CineFlash · Trasparenza"
        title="Permessi"
        subtitle="Cosa l'app usa, perché lo usa e come cambiarlo: tutto in un posto, senza sorprese."
      />

      <GlassCard style={{ marginTop: 16 }}>
        <Row
          icon="🔔"
          title="Notifiche"
          body="Avvisi per prevendite aperte e notizie importanti. L'app controlla i feed ogni minuto in primo piano e periodicamente in background."
          status={notif}
          onAsk={askNotif}
          toggleValue={settings.notifyEnabled !== false}
          onToggle={(v) => {
            Haptics.selectionAsync();
            update({ notifyEnabled: v });
            if (v && notif !== "granted") askNotif();
          }}
        />
        <View style={styles.sep} />
        <Row
          icon="🖼️"
          title="Fototeca"
          body="Serve solo quando tocchi “Salva il poster” nella scheda di un film: l'immagine finisce nella tua fototeca, nulla viene letto o inviato."
          status={media}
          onAsk={askMedia}
        />
        <View style={styles.sep} />
        <Row
          icon="📍"
          title="Posizione (mentre usi l'app)"
          body="Solo se tocchi “Ordina per distanza” durante la prenotazione: trova i cinema più vicini. Mai salvata né trasmessa."
          status={loc}
          onAsk={askLocation}
        />
      </GlassCard>

      <GlassCard style={{ marginTop: 12 }}>
        <Text style={s.sectionTitle}>La promessa</Text>
        <Text style={styles.promise}>
          🔒 Nessun account, nessun tracker, nessun analytics. L'AI gira sul
          telefono e i tuoi dati restano nel device. Puoi revocare qualsiasi
          permesso quando vuoi da qui o dalle Impostazioni di sistema.
        </Text>
      </GlassCard>

      <GlassButton label="Apri le Impostazioni di sistema" onPress={openOS} />
      <Text style={styles.foot}>
        CineFlash funziona anche senza nessun permesso: le notifiche e la
        posizione abilitano solo le funzioni extra.
      </Text>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  row: {
    alignItems: "flex-start",
    paddingVertical: 12,
    gap: 12,
  },
  rowIcon: { fontSize: 20, marginTop: 2 },
  rowTitle: { color: theme.colors.text, fontSize: 15, fontWeight: "800" },
  rowBody: { color: theme.colors.textDim, fontSize: 12, lineHeight: 18, marginTop: 4 },
  stateChip: {
    marginLeft: 8,
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 999,
  },
  stateText: { fontSize: 9, fontWeight: "800", letterSpacing: 0.8 },
  askBtn: {
    alignSelf: "flex-start",
    marginTop: 8,
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: theme.colors.border,
    backgroundColor: theme.colors.surfaceAlt,
  },
  askText: { color: theme.colors.accent, fontSize: 12, fontWeight: "800" },
  sep: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: theme.colors.border,
  },
  promise: { color: theme.colors.textDim, fontSize: 13, lineHeight: 19 },
  foot: {
    color: theme.colors.textDim,
    fontSize: 11,
    textAlign: "center",
    marginTop: 16,
  },
});
