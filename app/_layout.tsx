import { useEffect } from "react";
import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { StoreProvider, useStoreContext } from "../src/storage/StoreContext";
import { theme } from "../src/theme";
import { startAIBootstrap } from "../src/logic/localAI";

/** Avvia la preparazione dell'AI (download + caricamento) all'apertura dell'app. */
function AIBootstrap() {
  const { settings } = useStoreContext();
  useEffect(() => {
    if (settings.aiDisabled) return;
    startAIBootstrap(settings.aiModelKey).catch(() => {});
  }, [settings.aiModelKey, settings.aiDisabled]);
  return null;
}

export default function RootLayout() {
  return (
    <StoreProvider>
      <StatusBar style="light" />
      <AIBootstrap />
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: theme.colors.bg },
        }}
      >
        <Stack.Screen name="(tabs)" />
      </Stack>
    </StoreProvider>
  );
}
