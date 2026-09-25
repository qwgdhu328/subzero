import { Platform, StyleSheet, TextStyle, ViewStyle } from "react-native";

/**
 * Tema "sala proiezione": nero profondo, superfici antracite,
 * oro champagne da marquee come accento.
 */
export const theme = {
  colors: {
    bg: "#0A0A0F",
    surface: "#14141C",
    surfaceAlt: "#1C1C28",
    border: "#2A2A3A",
    text: "#F2F0EA",
    textDim: "#9A97A8",
    accent: "#EFC44F", // oro champagne
    accentDark: "#2e2c27",
    danger: "#FF5A5F",
    warn: "#F5A623",
    ok: "#3ECF8E",
    money: "#EFC44F",
    bgGradTop: "#12101A",
    bgGradBottom: "#0A0A0F",
    surfaceRaised: "#1A1A26",
    dangerBg: "#FF5A5F22",
  },
  radius: {
    xs: 8,
    sm: 12,
    md: 16,
    lg: 22,
    xl: 28,
  },
  spacing: {
    xs: 4,
    sm: 8,
    md: 12,
    lg: 16,
    xl: 24,
    xxl: 32,
  },
} as const;

/**
 * Volto editoriale della testata: serif per masthead e copertina.
 * Georgia è di sistema su iOS/web, "serif" mappa su Noto Serif su Android.
 */
export const fonts = {
  serif: Platform.select({
    ios: "Georgia",
    android: "serif",
    default: "Georgia, serif",
  }) as string,
  /** Famiglia UI: Avenir Next su iOS, sans di sistema altrove. */
  ui: Platform.select({
    ios: "Avenir Next",
    android: "sans-serif",
    default: "system-ui, sans-serif",
  }) as string,
} as const;

const base = StyleSheet.create({
  flex1: { flex: 1 } as ViewStyle,
  row: { flexDirection: "row", alignItems: "center" } as ViewStyle,
  spaced: { justifyContent: "space-between" } as ViewStyle,
  grow: { flex: 1 } as ViewStyle,
  screen: {
    flex: 1,
    backgroundColor: theme.colors.bg,
  } as ViewStyle,
  screenPad: {
    flex: 1,
    backgroundColor: theme.colors.bg,
    padding: theme.spacing.lg,
  } as ViewStyle,
  card: {
    backgroundColor: theme.colors.surface,
    borderRadius: theme.radius.md,
    borderWidth: 1,
    borderColor: theme.colors.border,
    padding: theme.spacing.lg,
  } as ViewStyle,
  sectionTitle: {
    color: theme.colors.textDim,
    fontSize: 12,
    fontWeight: "700",
    letterSpacing: 1.2,
    textTransform: "uppercase",
    marginBottom: theme.spacing.sm,
  } as TextStyle,
  h1: {
    color: theme.colors.text,
    fontSize: 30,
    fontWeight: "900",
    letterSpacing: -0.5,
  } as TextStyle,
  moneyBig: {
    color: theme.colors.text,
    fontSize: 38,
    fontWeight: "900",
    fontVariant: ["tabular-nums"],
    letterSpacing: -1,
  } as TextStyle,

  /* Voce editoriale: occhiello sopra i titoli delle pagine */
  eyebrow: {
    color: theme.colors.accent,
    fontSize: 10,
    fontWeight: "800",
    letterSpacing: 3,
    textTransform: "uppercase",
  } as TextStyle,
  /* Titolo serif per masthead e copertine */
  serifTitle: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 32,
    fontWeight: "700",
    letterSpacing: -0.5,
    marginTop: 4,
  } as TextStyle,
  /* Titolo di sezione serif, più contenuto */
  serifH2: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 20,
    fontWeight: "700",
    lineHeight: 24,
  } as TextStyle,
  /* Separatore hairline verticale flessibile (da affiancare a label) */
  hairline: {
    flex: 1,
    height: StyleSheet.hairlineWidth,
    backgroundColor: theme.colors.border,
  } as ViewStyle,
  /* Riga di metadati (fonte · tempo) */
  meta: {
    color: theme.colors.textDim,
    fontSize: 11,
    fontWeight: "600",
  } as TextStyle,
});

export const styles = base;
