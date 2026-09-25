import { NativeTabs } from "expo-router/native-tabs";
import type { SFSymbol } from "sf-symbols-typescript";
import { theme } from "../../src/theme";

/**
 * Tab bar NATIVA: UITabBarController di iOS (Liquid Glass su iOS 26),
 * Material Bottom Navigation su Android, fallback JS sul web.
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
        <NativeTabs.Trigger.Label>Notizie</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>

      <NativeTabs.Trigger name="movies">
        <NativeTabs.Trigger.Icon sf={"film" as SFSymbol} />
        <NativeTabs.Trigger.Label>Film</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>

      <NativeTabs.Trigger name="settings">
        <NativeTabs.Trigger.Icon sf={"gearshape" as SFSymbol} />
        <NativeTabs.Trigger.Label>Impostazioni</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
