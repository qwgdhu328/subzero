import React, { useCallback, useRef, useState } from "react";
import {
  ActivityIndicator,
  Animated,
  Dimensions,
  Easing,
  Pressable,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useRouter } from "expo-router";
import * as Haptics from "expo-haptics";
import { LinearGradient } from "expo-linear-gradient";
import { theme, fonts } from "../src/theme";
import { SPRING } from "../src/motion";
import { useStoreContext } from "../src/storage/StoreContext";

const { width } = Dimensions.get("window");

/** Curva "couture": ingressi lenti e decisi, da titoli di testa. */
const EASE_COUTURE = { duration: 560, easing: Easing.out(Easing.cubic) };

/* Le 4 scene + finale: la promessa del prodotto in 5 gesti. */
const SLIDES = [
  {
    eyebrow: "CineFlash",
    title: "Il cinema,\nin tempo reale",
    body: "Le notizie dai migliori giornali di cinema italiani, riscritte in parole chiare dalla redazione AI. Live, ogni minuto, sul tuo telefono.",
  },
  {
    eyebrow: "Redazione AI",
    title: "Un redattore AI\nsempre con te",
    body: "Un'intelligenza che spiega le notizie, presenta i film e risponde alle tue domande. Già pronta, nessun download: si usa subito.",
  },
  {
    eyebrow: "Catalogo",
    title: "Tutto il cinema\nin una griglia",
    body: "Ora al cinema, in uscita, popolari: poster, voti, trailer in-app e prevendite avvisate con una notifica. La watchlist resta sul telefono, come deve.",
  },
  {
    eyebrow: "Privacy",
    title: "Tuo. Solo tuo.",
    body: "Nessun account, nessun tracker, nessun analytics. Le tue liste e le tue letture restano solo tue, sul telefono.",
  },
  {
    eyebrow: "Si accendono le luci",
    title: "Pronto?",
    body: "La redazione AI è già al lavoro: i primi articoli arriveranno tra qualche secondo.",
  },
] as const;

const ABS = {
  position: "absolute" as const,
  top: 0,
  left: 0,
  right: 0,
  bottom: 0,
};

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: theme.colors.bg },
  rootFill: { ...ABS, backgroundColor: "transparent" },
  flash: { ...ABS, backgroundColor: theme.colors.text },
  spotlight: { ...ABS },
  scene: {
    ...ABS,
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 34,
  },
  eyebrow: {
    color: theme.colors.accent,
    fontSize: 11,
    fontWeight: "800",
    letterSpacing: 4,
    textTransform: "uppercase",
    marginBottom: 18,
  },
  title: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: Math.round(width * 0.088),
    fontWeight: "700",
    textAlign: "center",
    lineHeight: Math.round(width * 0.118),
    letterSpacing: -0.5,
  },
  body: {
    color: theme.colors.textDim,
    fontSize: 15,
    lineHeight: 23,
    textAlign: "center",
    marginTop: 16,
    maxWidth: 320,
  },
  tipWrap: {
    position: "absolute",
    bottom: 168,
    left: 0,
    right: 0,
    alignItems: "center",
  },
  tipText: {
    color: theme.colors.textDim,
    fontSize: 12,
    textAlign: "center",
    opacity: 0.9,
  },
  footer: { position: "absolute", left: 0, right: 0, bottom: 44 },
  counterRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: theme.colors.border,
  },
  dotOn: { backgroundColor: theme.colors.accent, width: 22 },
  primaryCta: {
    alignSelf: "stretch",
    marginHorizontal: 34,
    marginTop: 22,
    paddingVertical: 16,
    borderRadius: 999,
    backgroundColor: theme.colors.accent,
    alignItems: "center",
    shadowColor: theme.colors.text,
    shadowOpacity: 0.18,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 6 },
    elevation: 3,
  },
  primaryCtaText: {
    color: theme.colors.onAccent,
    fontSize: 16,
    fontWeight: "900",
    letterSpacing: 0.8,
  },
  skipRow: { alignItems: "center", marginTop: 14 },
  skip: {
    color: theme.colors.textDim,
    fontSize: 13,
    fontWeight: "600",
    paddingHorizontal: 24,
    paddingVertical: 10,
  },
});

export default function OnboardingScreen() {
  const router = useRouter();
  const { update } = useStoreContext();

  const [index, setIndex] = useState(0);
  const [finishing, setFinishing] = useState(false);
  const anim = useRef(new Animated.Value(0)).current;
  const flash = useRef(new Animated.Value(0)).current;
  const cta = useRef(new Animated.Value(0)).current;
  const spot = useRef(new Animated.Value(0)).current;
  const lastTap = useRef(0);

  /** Ingresso della scena: dolly-in editoriale (slide + fade + zoom). */
  const playScene = useCallback(() => {
    anim.setValue(0);
    Animated.timing(anim, { toValue: 1, ...EASE_COUTURE, useNativeDriver: true }).start();
  }, [anim]);

  React.useEffect(() => {
    playScene();
  }, [index, playScene]);

  /* Il CTA finale entra con la scena 5: spring iconico. */
  React.useEffect(() => {
    if (index === SLIDES.length - 1) {
      cta.setValue(0);
      Animated.spring(cta, { toValue: 1, ...SPRING.cinematic, useNativeDriver: true }).start();
    }
  }, [index, cta]);

  /** Fine: flash da cambio bobina, si accende il "proiettore", si entra nell'app. */
  const finish = useCallback(() => {
    setFinishing(true);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
    Animated.parallel([
      Animated.sequence([
        Animated.timing(flash, { toValue: 1, duration: 140, useNativeDriver: true }),
        Animated.timing(flash, { toValue: 0, duration: 320, useNativeDriver: true }),
      ]),
      Animated.timing(spot, { toValue: 1, duration: 600, useNativeDriver: false }),
    ]).start(() => {
      update({ onboarded: true });
      // Deep link alla vetrina AI: il cuore del prodotto è il primo schermo
      // che l'utente incontra dopo l'intro.
      router.replace("/(tabs)/ai-tab");
    });
  }, [flash, spot, router, update]);

  const next = useCallback(() => {
    const now = Date.now();
    if (now - lastTap.current < 450) return; // dedup tocchi multipli
    lastTap.current = now;
    if (index < SLIDES.length - 1) setIndex(index + 1);
    else finish();
  }, [index, finish]);

  const back = useCallback(() => {
    if (index > 0) setIndex(index - 1);
  }, [index]);

  const slide = SLIDES[index];
  const isLast = index === SLIDES.length - 1;
  const spotOpacity = spot.interpolate({ inputRange: [0, 1], outputRange: [0, 1] });
  const flashOpacity = flash;

  return (
    <View style={styles.root}>
      {/* Fondo "sala di proiezione": gradiente verticale profondo */}
      <LinearGradient
        colors={[theme.colors.bgGradTop, theme.colors.bgGradBottom]}
        style={styles.rootFill}
      />
      {/* Fascio di luce che si accende solo al momento dell'avvio */}
      <Animated.View style={[styles.spotlight, { opacity: spotOpacity }]} pointerEvents="none">
        <LinearGradient
          colors={[theme.colors.accent + "30", "transparent"]}
          start={{ x: 0.5, y: 0 }}
          end={{ x: 0.5, y: 1 }}
          style={StyleSheet.absoluteFill}
        />
      </Animated.View>

      {/* Scena animata: ingresso slide + fade + leggero zoom (dolly-in) */}
      <Animated.View
        style={[
          styles.scene,
          {
            opacity: anim,
            transform: [
              { translateX: anim.interpolate({ inputRange: [0, 1], outputRange: [36, 0] }) },
              { scale: anim.interpolate({ inputRange: [0, 1], outputRange: [0.96, 1] }) },
            ],
          },
        ]}
        pointerEvents="none"
      >
        <Animated.Text style={[styles.eyebrow, { opacity: anim }]}>{slide.eyebrow}</Animated.Text>
        <Text style={styles.title}>{slide.title}</Text>
        <Text style={styles.body}>{slide.body}</Text>
      </Animated.View>

      {/* Zone di tocco: avanti ovunque, indietro sul bordo sinistro */}
      <Pressable style={StyleSheet.absoluteFill} onPress={next} />
      {index > 0 && (
        <Pressable
          style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: 72 }}
          onPress={back}
        />
      )}

      {/* Tip solo sulla prima scena */}
      {index === 0 && (
        <View style={styles.tipWrap} pointerEvents="none">
          <Text style={styles.tipText}>Tocca lo schermo per continuare</Text>
        </View>
      )}

      {/* Footer: punti di progresso + CTA */}
      <View style={styles.footer} pointerEvents="box-none">
        <View style={styles.counterRow} pointerEvents="none">
          {SLIDES.map((_, i) => (
            <View key={i} style={[styles.dot, i === index && styles.dotOn]} />
          ))}
        </View>
        {isLast ? (
          <Animated.View
            style={{
              opacity: cta,
              transform: [
                { translateY: cta.interpolate({ inputRange: [0, 1], outputRange: [18, 0] }) },
                { scale: cta.interpolate({ inputRange: [0, 1], outputRange: [0.9, 1] }) },
              ],
            }}
          >
            <Pressable
              onPress={finish}
              disabled={finishing}
              style={({ pressed }) => [styles.primaryCta, pressed && { opacity: 0.85 }]}
            >
              {finishing ? (
                <ActivityIndicator color={theme.colors.onAccent} />
              ) : (
                <Text style={styles.primaryCtaText}>Inizia</Text>
              )}
            </Pressable>
            <Pressable
              onPress={() => {
                update({ onboarded: true });
                router.replace("/(tabs)");
              }}
              style={styles.skipRow}
            >
              <Text style={styles.skip}>Salta</Text>
            </Pressable>
          </Animated.View>
        ) : (
          <Pressable
            onPress={next}
            style={({ pressed }) => [styles.primaryCta, pressed && { opacity: 0.85 }]}
          >
            <Text style={styles.primaryCtaText}>Avanti</Text>
          </Pressable>
        )}
      </View>

      {/* Flash bianco da cambio bobina (sopra tutto, solo all'ingresso) */}
      <Animated.View style={[styles.flash, { opacity: flashOpacity }]} pointerEvents="none" />
    </View>
  );
}
