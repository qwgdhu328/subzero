import React from "react";
import { StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { ScreenHeader } from "../../src/components/ScreenHeader";
import { ChatView } from "../../src/components/ChatView";
import { theme } from "../../src/theme";
import { styles as s } from "../../src/theme";

/**
 * Tab ✨ AI — chat-first, senza intermediari: apri, scrivi, risponde.
 * La barra di scrittura è fissa in basso; nessun overlay la copre mai.
 */
export default function AITabScreen() {
  const insets = useSafeAreaInsets();

  return (
    <View style={s.screen}>
      {/* Masthead compatto sopra la chat */}
      <View style={[styles.header, { paddingTop: 12 + insets.top }]}>
        <ScreenHeader
          eyebrow="CineFlash · AI gratuita"
          title="AI"
          subtitle="Chiedi alla tua redazione privata: notizie, film, curiosità."
        />
      </View>

      {/* La chat è la pagina: la barra di scrittura resta in basso */}
      <View style={styles.chatArea}>
        <ChatView context={{}} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: 16,
    paddingBottom: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: theme.colors.border,
    backgroundColor: theme.colors.bg,
  },
  chatArea: {
    flex: 1,
  },
});
