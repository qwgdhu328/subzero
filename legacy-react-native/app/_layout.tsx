import { ActivityIndicator, View } from "react-native";
import { Redirect, Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { StoreProvider, useStoreContext } from "../src/storage/StoreContext";
import { ErrorBoundary } from "../src/components/ErrorBoundary";
import { theme } from "../src/theme";

/** Splash minimale durante il caricamento delle impostazioni. */
function Splash() {
  return (
    <View
      style={{
        flex: 1,
        backgroundColor: theme.colors.bg,
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <ActivityIndicator color={theme.colors.accent} />
    </View>
  );
}

/**
 * Gating del primo avvio: finché le impostazioni non sono caricate mostra lo
 * splash; se l'intro cinematografica non è stata vista manda a /onboarding,
 * altrimenti lascia entrare nelle tab. L'AI è gratuita e nel cloud: nessun
 * modello da scaricare, la chat è pronta subito.
 */
function RootGate() {
  const { settings, loading } = useStoreContext();

  if (loading) return <Splash />;

  return (
    <>
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: theme.colors.bg },
        }}
      >
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="onboarding" />
      </Stack>
      {!settings.onboarded && <Redirect href="/onboarding" />}
    </>
  );
}

export default function RootLayout() {
  return (
    <StoreProvider>
      <StatusBar style="dark" />
      <ErrorBoundary>
        <RootGate />
      </ErrorBoundary>
    </StoreProvider>
  );
}
