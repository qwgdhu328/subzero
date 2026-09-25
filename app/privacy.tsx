import React from "react";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { Stack, useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import { GlassView } from "expo-glass-effect";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { theme, fonts } from "../src/theme";
import { styles as s } from "../src/theme";

/**
 * Privacy policy dell'app, mostrata dentro l'app (richiesta da Apple 5.1.1(i)
 * e Google Play User Data). Riflette il comportamento REALE del codice:
 * dati solo in locale, nessun account, nessun analytics, AI on-device.
 */
export default function PrivacyScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();

  return (
    <View style={s.screen}>
      <Stack.Screen options={{ headerShown: false }} />
      <ScrollView
        contentContainerStyle={[
          styles.wrap,
          { paddingTop: 14 + insets.top, paddingBottom: 40 + insets.bottom },
        ]}
      >
        <View style={[s.row, styles.headerRow]}>
          <PressableBack onPress={() => router.back()} />
        </View>
        <Text style={s.eyebrow}>CineFlash · Privacy</Text>
        <Text style={styles.masthead}>Informativa privacy</Text>
        <Text style={styles.updated}>Ultimo aggiornamento: 19 settembre 2026</Text>

        <Section title="In breve">
          <P>
            CineFlash funziona senza account e senza registrazione. Le tue
            liste (notizie salvate, watchlist, promemoria, impostazioni) restano{" "}
            <B>solo sul tuo dispositivo</B> e non vengono inviate ad alcun
            server nostro. Non raccogliamo, vendiamo o condividiamo dati
            personali. Non usiamo analytics, pubblicità o tracker.
          </P>
        </Section>

        <Section title="Dati che l'app salva sul telefono">
          <Bullet>Notizie salvate e cache delle notizie (per la lettura offline)</Bullet>
          <Bullet>Watchlist dei film e promemoria di uscita</Bullet>
          <Bullet>Impostazioni: fonti RSS, chiave TMDB personale (se ne inserisci una), preferenze AI</Bullet>
          <Bullet>
            Se attivi “Ordina i cinema per distanza”, la posizione è usata{" "}
            <B> solo in memoria</B> per calcolare la distanza dei cinema:
            non viene salvata né inviata da CineFlash.
          </Bullet>
        </Section>

        <Section title="AI locale (✨)">
          <P>
            La funzione “Spiega con l'AI” usa un modello linguistico che gira{" "}
            <B>interamente sul tuo telefono</B> (llama.cpp). Il modello si
            scarica una sola volta da Hugging Face e resta sul dispositivo.
            Notizie e film che analizziamo con l'AI <B>non lasciano mai</B> il
            telefono: nessuna richiesta viene inviata a server di AI online.
            Puoi disattivare l'AI dalle Impostazioni o eliminare il modello per
            liberare spazio.
          </P>
        </Section>

        <Section title="Servizi di terze parti usati per i contenuti">
          <Bullet>
            <B>Feed RSS delle testate</B> che scegli di seguire: l'app scarica
            i titoli e i riassuni pubblici dei siti di cinema.
          </Bullet>
          <Bullet>
            <B>TMDB</B> (The Movie Database) e <B>iTunes Search API di Apple</B>:
            cataloghi film, poster, voti e trailer. Le richieste contengono solo
            la ricerca o l'ID del film, non dati personali.
          </Bullet>
          <Bullet>
            <B>OpenStreetMap (Overpass)</B>: elenco dei cinema della città che
            cerchi quando prenoti. Nessun dato personale è coinvolto.
          </Bullet>
          <Bullet>
            <B>Siti dei cinema</B>: quando prenoti, si apre nel browser il sito
            del cinema (o una ricerca Google con nome del cinema e film).
            A quel punto si applicano le politiche di quel sito.
          </Bullet>
        </Section>

        <Section title="Articoli dentro l'app">
          <P>
            Gli articoli si aprono in una schermata integrata che{" "}
            <B>blocca attivamente</B> i domini pubblicitari e di tracking più
            diffusi (doubleclick, taboola, outbrain, Google Ads e altri). Il
            sito originale, però, può avere le sue cookie policy: consultale
            sul sito della testata.
          </P>
        </Section>

        <Section title="Permesso posizione (iOS)">
          <P>
            CineFlash richiede l'accesso alla posizione{" "}
            <B>solo quando tocchi “Ordina i cinema per distanza”</B> durante la
            prenotazione. Il permesso è “mentre usi l'app”: se lo neghi, la
            prenotazione funziona comunque, con i cinema in ordine alfabetico.
          </P>
        </Section>

        <Section title="Notifiche">
          <P>
            Se attivi gli avvisi, l'app programma notifiche locali sul tuo
            dispositivo (nuove notizie, aperture prevendite, uscite dei film che
            segui). Le notifiche non passano da server esterni: nascono sul
            telefono. Puoi disattivarle dalle Impostazioni o da iOS.
          </P>
        </Section>

        <Section title="Cancellazione dei dati">
          <P>
            Non essendoci account, non c'è nulla da cancellare sui nostri
            server. Per rimuovere ogni dato: disinstalla l'app, oppure da iOS
            “Impostazioni → Generali → Spazio iPhone → CineFlash → Cancella app”.
            Questo elimina cache, liste e il modello AI scaricato.
          </P>
        </Section>

        <Section title="Bambini">
          <P>
            L'app non è diretta ai minori di 13 anni e non raccoglie alcun dato,
            quindi non tratta consapevolmente dati di minori.
          </P>
        </Section>

        <Section title="Contatti">
          <P>
            Domande su questa informativa? Scrivi a{" "}
            <B>privacy@cineflash.app</B>.
          </P>
        </Section>
      </ScrollView>
    </View>
  );
}

function PressableBack({ onPress }: { onPress: () => void }) {
  return (
    <Pressable onPress={onPress} hitSlop={10}>
      <GlassView glassEffectStyle="clear" isInteractive style={styles.backBtn}>
        <Text style={styles.backText}>‹</Text>
      </GlassView>
    </Pressable>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      {children}
    </View>
  );
}

function P({ children }: { children: React.ReactNode }) {
  return <Text style={styles.p}>{children}</Text>;
}

function Bullet({ children }: { children: React.ReactNode }) {
  return (
    <View style={styles.bulletRow}>
      <Text style={styles.bulletDot}>·</Text>
      <Text style={styles.bulletText}>{children}</Text>
    </View>
  );
}

function B({ children }: { children: React.ReactNode }) {
  return <Text style={{ fontWeight: "800" }}>{children}</Text>;
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
    fontSize: 32,
    fontWeight: "700",
    letterSpacing: -0.5,
    lineHeight: 38,
    marginTop: 6,
  },
  updated: {
    color: theme.colors.textDim,
    fontSize: 11,
    marginTop: 6,
    marginBottom: 4,
  },
  section: { marginTop: 22 },
  sectionTitle: {
    color: theme.colors.accent,
    fontSize: 11,
    fontWeight: "800",
    letterSpacing: 2,
    textTransform: "uppercase",
    marginBottom: 8,
  },
  p: {
    color: theme.colors.text,
    fontSize: 14,
    lineHeight: 21,
  },
  bulletRow: { flexDirection: "row", marginBottom: 8, paddingRight: 8 },
  bulletDot: { color: theme.colors.accent, fontSize: 14, fontWeight: "800", marginRight: 8 },
  bulletText: { color: theme.colors.text, fontSize: 13.5, lineHeight: 20, flex: 1 },
});
