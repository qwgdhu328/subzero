import React from "react";
import {
  ActivityIndicator,
  Image,
  ImageStyle,
  Modal,
  Platform,
  Pressable,
  StyleProp,
  StyleSheet,
  Text,
  TextInput as RNTextInput,
  TextStyle,
  View,
  ViewStyle,
} from "react-native";
import { GlassView } from "expo-glass-effect";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { theme, fonts } from "../theme";

/**
 * Bottone con Liquid Glass nativo su iOS 26+: GlassView interattivo con tint.
 * Su iOS senza Liquid Glass usa un vetro translucido finto; su Android/web
 * ricade sul tasto pieno standard.
 */
export function LiquidButton({
  label,
  onPress,
  filled,
  disabled,
}: {
  label: string;
  onPress: () => void;
  /** Tinta col colore d'accento; false = vetro neutro ("clear"). */
  filled?: boolean;
  disabled?: boolean;
}) {
  const glass = (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        base.glassBtn,
        Platform.OS !== "ios" && base.glassBtnFallback,
        filled && base.glassBtnFilled,
        (pressed || disabled) && { opacity: 0.7 },
      ]}
    >
      <Text style={[base.glassBtnText, filled && base.glassBtnTextFilled]}>{label}</Text>
    </Pressable>
  );

  if (Platform.OS !== "ios") return glass;

  // iOS 26+: vetro liquido nativo, interattivo quando c'e' un'azione
  return (
    <GlassView
      glassEffectStyle={filled ? "regular" : "clear"}
      tintColor={filled ? theme.colors.accent : undefined}
      isInteractive={!disabled}
      style={base.glassBtnWrap}
    >
      {glass}
    </GlassView>
  );
}

/**
 * Card minimal in vetro: Liquid Glass nativo su iOS 26,
 * fallback opaco sobrio su altre piattaforme.
 */
export function GlassCard({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
}) {
  if (Platform.OS !== "ios") {
    return <View style={[base.glassCard, style]}>{children}</View>;
  }
  return (
    <GlassView glassEffectStyle="regular" style={[base.glassCard, style]}>
      {children}
    </GlassView>
  );
}

/** Bottone minimale: vetro liquido nativo su iOS 26+, translucido altrimenti. */
export function GlassButton({
  label,
  onPress,
  filled,
}: {
  label: string;
  onPress: () => void;
  filled?: boolean;
}) {
  return <LiquidButton label={label} onPress={onPress} filled={filled} />;
}

export function Card({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
}) {
  return <View style={[base.card, style]}>{children}</View>;
}

export function Badge({ label, tone }: { label: string; tone: "warn" | "danger" | "ok" | "accent" }) {
  return (
    <View
      style={[
        base.badge,
        tone === "warn" && { backgroundColor: theme.colors.warn + "1A" },
        tone === "danger" && { backgroundColor: theme.colors.danger + "1A" },
        tone === "ok" && { backgroundColor: theme.colors.ok + "1A" },
        tone === "accent" && { backgroundColor: theme.colors.accent + "1A" },
      ]}
    >
      <Text
        style={[
          base.badgeText,
          {
            color:
              tone === "warn"
                ? theme.colors.warn
                : tone === "danger"
                  ? theme.colors.danger
                  : tone === "ok"
                    ? theme.colors.ok
                    : theme.colors.accent,
          },
        ]}
      >
        {label}
      </Text>
    </View>
  );
}

export function Button({
  label,
  onPress,
  variant = "primary",
  disabled,
}: {
  label: string;
  onPress: () => void;
  variant?: "primary" | "ghost" | "danger";
  disabled?: boolean;
}) {
  const solidDanger = variant === "danger";
  if (solidDanger) {
    return (
      <Pressable
        onPress={onPress}
        disabled={disabled}
        style={({ pressed }) => [
          base.btn,
          base.btnDanger,
          pressed && { opacity: 0.7 },
          disabled && { opacity: 0.4 },
        ]}
      >
        <Text style={[base.btnText, { color: theme.colors.bg }]}>{label}</Text>
      </Pressable>
    );
  }
  // primary e ghost: Liquid Glass nativo su iOS 26+
  return (
    <LiquidButton
      label={label}
      onPress={onPress}
      filled={variant === "primary"}
      disabled={disabled}
    />
  );
}

export function Spinner({ label }: { label?: string }) {
  return (
    <View style={base.spinnerWrap}>
      <ActivityIndicator color={theme.colors.accent} size="large" />
      {label ? <Text style={base.spinnerLabel}>{label}</Text> : null}
    </View>
  );
}

export function EmptyState({
  icon,
  title,
  subtitle,
}: {
  icon: string;
  title: string;
  subtitle?: string;
}) {
  return (
    <View style={base.emptyWrap}>
      <Text style={{ fontSize: 40, marginBottom: 10 }}>{icon}</Text>
      <Text style={base.emptyTitle}>{title}</Text>
      {subtitle ? <Text style={base.emptySub}>{subtitle}</Text> : null}
    </View>
  );
}

export function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <View style={{ marginBottom: 14 }}>
      <Text style={base.fieldLabel}>{label}</Text>
      {children}
    </View>
  );
}

export function TextInput({
  value,
  onChangeText,
  placeholder,
  autoCapitalize,
}: {
  value: string;
  onChangeText: (t: string) => void;
  placeholder?: string;
  autoCapitalize?: "none" | "sentences" | "words";
}) {
  return (
    <View style={base.inputWrap}>
      <RNTextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={theme.colors.textDim}
        autoCapitalize={autoCapitalize}
        style={base.input}
      />
    </View>
  );
}

export function ModalSheet({
  visible,
  onClose,
  title,
  children,
}: {
  visible: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
}) {
  const insets = useSafeAreaInsets();
  return (
    <Modal visible={visible} animationType="slide" transparent onRequestClose={onClose}>
      <View style={base.sheetOverlay}>
        <Pressable style={base.sheetBackdrop} onPress={onClose} />
        <View style={[base.sheetPanel, { paddingBottom: 28 + insets.bottom }]}>
          <View style={base.sheetHandle} />
          <View style={[base.row, base.spaced, { marginBottom: 12 }]}>
            <Text style={base.sheetTitle} numberOfLines={2}>
              {title}
            </Text>
            <Pressable onPress={onClose} hitSlop={12}>
              <Text style={base.sheetClose}>✕</Text>
            </Pressable>
          </View>
          {children}
        </View>
      </View>
    </Modal>
  );
}

/** Poster con placeholder mentre carica e fallback se manca. */
export function Poster({
  uri,
  style,
}: {
  uri: string | null;
  style?: StyleProp<ImageStyle>;
}) {
  const [failed, setFailed] = React.useState(false);
  React.useEffect(() => setFailed(false), [uri]);

  if (!uri || failed) {
    return (
      <View style={[base.posterFallback, style]}>
        <Text style={{ fontSize: 28 }}>🎬</Text>
      </View>
    );
  }
  return (
    <Image
      source={{ uri }}
      style={[base.posterBase, style]}
      resizeMode="cover"
      onError={() => setFailed(true)}
    />
  );
}

const base = StyleSheet.create({
  card: {
    backgroundColor: theme.colors.surface,
    borderRadius: theme.radius.md,
    borderWidth: 1,
    borderColor: theme.colors.border,
    padding: theme.spacing.lg,
  } as ViewStyle,
  glassCard: {
    borderRadius: theme.radius.md,
    padding: theme.spacing.lg,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: "rgba(255,255,255,0.12)",
    ...Platform.select({
      ios: { backgroundColor: "transparent" },
      default: { backgroundColor: theme.colors.surface },
    }),
  } as ViewStyle,
  glassBtnWrap: { borderRadius: theme.radius.sm, marginTop: 6 } as ViewStyle,
  glassBtn: {
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: theme.radius.sm,
    alignItems: "center" as const,
    justifyContent: "center" as const,
  } as ViewStyle,
  glassBtnFallback: {
    backgroundColor: "rgba(255,255,255,0.10)",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: "rgba(255,255,255,0.14)",
  } as ViewStyle,
  glassBtnFilled: {
    backgroundColor: "rgba(245, 197, 24, 0.9)",
  } as ViewStyle,
  glassBtnText: {
    color: theme.colors.text,
    fontFamily: fonts.ui,
    fontWeight: "600",
    fontSize: 14,
    letterSpacing: 0.2,
  } as TextStyle,
  glassBtnTextFilled: {
    color: theme.colors.bg,
    fontFamily: fonts.ui,
    fontWeight: "700",
    fontSize: 14,
    letterSpacing: 0.2,
  } as TextStyle,
  badge: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: theme.radius.xs,
    alignSelf: "flex-start",
  } as ViewStyle,
  badgeText: { fontSize: 9, fontWeight: "800", letterSpacing: 1 } as TextStyle,
  btn: {
    paddingVertical: 14,
    borderRadius: theme.radius.sm,
    alignItems: "center",
    justifyContent: "center",
    marginTop: 6,
  } as ViewStyle,
  btnPrimary: { backgroundColor: theme.colors.accent } as ViewStyle,
  btnGhost: { backgroundColor: "transparent" } as ViewStyle,
  btnDanger: { backgroundColor: theme.colors.danger } as ViewStyle,
  btnText: {
    color: theme.colors.bg,
    fontWeight: "800",
    fontSize: 15,
  } as TextStyle,
  spinnerWrap: { alignItems: "center", justifyContent: "center", padding: 40 } as ViewStyle,
  spinnerLabel: {
    color: theme.colors.textDim,
    fontSize: 13,
    marginTop: 12,
  } as TextStyle,
  emptyWrap: { alignItems: "center", padding: 32 } as ViewStyle,
  emptyTitle: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 18,
    fontWeight: "700",
  } as TextStyle,
  emptySub: {
    color: theme.colors.textDim,
    fontSize: 13,
    textAlign: "center",
    marginTop: 6,
    lineHeight: 19,
  } as TextStyle,
  sheetOverlay: { flex: 1, justifyContent: "flex-end" } as ViewStyle,
  sheetBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.6)" } as ViewStyle,
  sheetPanel: {
    backgroundColor: theme.colors.surface,
    borderTopLeftRadius: theme.radius.lg,
    borderTopRightRadius: theme.radius.lg,
    borderWidth: 1,
    borderColor: theme.colors.border,
    padding: theme.spacing.xl,
    paddingBottom: 40,
    maxHeight: "92%",
  } as ViewStyle,
  sheetHandle: {
    alignSelf: "center",
    width: 44,
    height: 5,
    borderRadius: 3,
    backgroundColor: theme.colors.border,
    marginBottom: 14,
  } as ViewStyle,
  sheetTitle: {
    fontFamily: fonts.serif,
    color: theme.colors.text,
    fontSize: 20,
    fontWeight: "700",
    flex: 1,
    paddingRight: 12,
    lineHeight: 25,
  } as TextStyle,
  sheetClose: {
    color: theme.colors.textDim,
    fontSize: 18,
    padding: 4,
  } as TextStyle,
  posterBase: {
    backgroundColor: theme.colors.surfaceAlt,
  } as ImageStyle,
  posterFallback: {
    backgroundColor: theme.colors.surfaceAlt,
    alignItems: "center",
    justifyContent: "center",
  } as ViewStyle,
  row: { flexDirection: "row", alignItems: "center" } as ViewStyle,
  spaced: { justifyContent: "space-between" } as ViewStyle,
  fieldLabel: {
    color: theme.colors.textDim,
    fontSize: 12,
    fontWeight: "700",
    marginBottom: 6,
    textTransform: "uppercase",
    letterSpacing: 0.8,
  } as TextStyle,
  inputWrap: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: theme.colors.surfaceAlt,
    borderRadius: theme.radius.sm,
    borderWidth: 1,
    borderColor: theme.colors.border,
    paddingHorizontal: 12,
  } as ViewStyle,
  input: {
    flex: 1,
    color: theme.colors.text,
    fontSize: 16,
    paddingVertical: 12,
  } as TextStyle,
});
