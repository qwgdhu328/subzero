import React from "react";
import { StyleProp, StyleSheet, ViewStyle } from "react-native";
import { useVideoPlayer, VideoView } from "expo-video";
import { WebView } from "react-native-webview";

/** Estrae l'ID video da un URL YouTube (watch, youtu.be, embed, shorts). */
function extractYouTubeId(url: string): string | null {
  const m =
    /(?:v=|youtu\.be\/|embed\/|shorts\/)([A-Za-z0-9_-]{11})/.exec(url) ??
    /^([A-Za-z0-9_-]{11})$/.exec(url.trim());
  return m ? m[1] : null;
}

/**
 * Player trailer in-app:
 * - mp4 (anteprime Apple/iTunes) → video nativo expo-video
 * - YouTube (TMDB) → embed WebView
 * Se non c'è niente, non renderizza nulla.
 */
export function TrailerPlayer({
  youtubeUrl,
  mp4Url,
  style,
}: {
  youtubeUrl?: string | null;
  mp4Url?: string | null;
  style?: StyleProp<ViewStyle>;
}) {
  // Hook sempre chiamato (regole dei lucidi di React)
  const player = useVideoPlayer(mp4Url ?? null, (p) => {
    p.loop = false;
  });

  if (mp4Url) {
    return (
      <VideoView
        player={player}
        style={style}
        contentFit="contain"
        fullscreenOptions={{ enable: true }}
        allowsPictureInPicture
        requiresLinearPlayback={false}
      />
    );
  }

  const key = youtubeUrl ? extractYouTubeId(youtubeUrl) : null;
  if (key) {
    return (
      <WebView
        source={{ uri: `https://www.youtube.com/embed/${key}?rel=0` }}
        style={[style, styles.webBg]}
        allowsFullscreenVideo
        javaScriptEnabled
        mediaPlaybackRequiresUserAction
        scrollEnabled={false}
      />
    );
  }

  return null;
}

const styles = StyleSheet.create({
  webBg: { backgroundColor: "#000" },
});
