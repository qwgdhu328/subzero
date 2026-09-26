import { NativeTabs } from "expo-router/native-tabs";
import type { SFSymbol } from "sf-symbols-typescript";
import { theme } from "../../src/theme";

/**
 * Tab bar: tre tab — Oggi (news editoriali), Catalogo (film), AI (chat).
 * Impostazioni non è più una tab: si raggiunge dall'ingranaggio negli header.
 * L'AI resta al centro: è la funzione che rende CineFlash diverso.
 */
export default function TabsLayout() {
  return (
    <NativeTabs
      tintColor={theme.colors.accent}
      iconColor={{
        default: theme.colors.textDim,
        selected: theme.colors.accent,
      }}
      labelStyle={{
        default: { color: theme.colors.textDim, fontSize: 11, fontWeight: "600" },
        selected: { color: theme.colors.accent, fontSize: 11, fontWeight: "700" },
      }}
      minimizeBehavior="onScrollDown"
    >
      <NativeTabs.Trigger name="index">
        <NativeTabs.Trigger.Icon sf={"newspaper" as SFSymbol} />
        <NativeTabs.Trigger.Label>Oggi</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>

      <NativeTabs.Trigger name="movies">
        <NativeTabs.Trigger.Icon sf={"film" as SFSymbol} />
        <NativeTabs.Trigger.Label>Catalogo</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>

      <NativeTabs.Trigger name="ai-tab">
        <NativeTabs.Trigger.Icon sf={"sparkles" as SFSymbol} />
        <NativeTabs.Trigger.Label>AI</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
