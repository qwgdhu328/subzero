import React, { useEffect, useState } from "react";
import { ActivityIndicator, Linking, Share, StyleSheet, Text, View } from "react-native";
import { theme } from "../theme";
import { styles as s } from "../theme";
import { fmtReleaseDate, posterUrl } from "../logic/tmdb";
import { Movie } from "../models/types";
import { Badge, Button, ModalSheet, Poster } from "./ui";
import { TrailerPlayer } from "./TrailerPlayer";
import * as Haptics from "expo-haptics";
import * as Notifications from "expo-notifications";
import { useReminders } from "../storage/collections";

export type DetailMovie = Movie & {
  trailerUrl?: string | null;
  runtime?: number | null;
  genres?: string[];
  itunesUrl?: string | null;
  previewUrl?: string | null;
  /** Descrizione estesa (film da iTunes). */
  longDescription?: string | null;
  /** Chiama TMDB per completare i dettagli (trailer, durata, generi). */
  needsTmdb?: boolean;
  /** Link all'articolo che ha citato il film (dalle pagine notizie). */
  articleUrl?: string | null;
  articleSource?: string | null;
};

/**
 * Foglio di dettaglio film condiviso: poster, voto, durata, generi, trailer
 * in-app, trama, promemoria uscita con notifica, watchlist, condivisione
 * e azioni AI. Usato da movies.tsx e dalle pagine prevendite/in-arrivo.
 */
export function MovieDetailSheet({
  movie,
  onClose,
  onOpenAI,
  watchlist,
  aiDisabled,
  onBook,
}: {
  movie: DetailMovie | null;
  onClose: () => void;
  onOpenAI: (m: DetailMovie) => void;
  watchlist: {
    isIn: (id: string) => boolean;
    toggle: (x: { id: string; title: string; posterPath: string | null }) => void;
  };
  aiDisabled?: boolean;
  /** Se presente, mostra il tasto "Prenota biglietti" (pagina prevendite). */
  onBook?: (m: DetailMovie) => void;
}) {
  const [loading, setLoading] = useState(false);
  const reminders = useReminders();
  const [reminderBusy, setReminderBusy] = useState(false);

  // Completa i dettagli via TMDB quando serve (le news non hanno trailer/runtime)
  useEffect(() => {
    let cancelled = false;
    if (!movie?.needsTmdb) return;
    (async () => {
      setLoading(true);
      try {
        const { fetchMovieDetails } = await import("../logic/tmdb");
        const { loadSettings } = await import("../storage/store");
        const st = await loadSettings();
        if (!st.tmdbApiKey) return;
        const d = await fetchMovieDetails(st.tmdbApiKey, movie.id);
        if (!cancelled) {
          movie.trailerUrl = d.trailerUrl;
          movie.runtime = d.runtime;
          movie.genres = d.genres;
        }
      } catch {
        // dettagli opzionali
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [movie?.id, movie?.needsTmdb]);

  if (!movie) return null;

  const inWatchlist = watchlist.isIn(String(movie.id));
  const hasReminder = reminders.has(movie.id);
  const isUpcomingMovie = isFutureRelease(movie.releaseDate);

  /** Notifica locale il giorno dell'uscita (alle 9:00). */
  const toggleReminder = async () => {
    if (reminderBusy) return;
    setReminderBusy(true);
    try {
      const added = await reminders.toggle({
        movieId: String(movie.id),
        title: movie.title,
        releaseDate: movie.releaseDate ?? "",
      });
      if (added && movie.releaseDate) {
        const fire = new Date(movie.releaseDate + "T09:00:00");
        if (fire.getTime() > Date.now()) {
          await Notifications.scheduleNotificationAsync({
            content: {
              title: "🎬 Esce oggi: " + movie.title,
              body: "Il film che aspettavi è al cinema. Dai un'occhiata ai biglietti!",
              sound: true,
            },
            trigger: { type: "date", date: fire.getTime() } as never,
          });
        }
      }
      Haptics.notificationAsync(
        added
          ? Haptics.NotificationFeedbackType.Success
          : Haptics.NotificationFeedbackType.Warning
      );
    } catch {
      // permesso notifiche negato o errore: il promemoria resta salvato localmente
    } finally {
      setReminderBusy(false);
    }
  };

  const shareMovie = async () => {
    try {
      const what = movie.releaseDate && isFutureRelease(movie.releaseDate)
        ? `${movie.title} — esce il ${fmtReleaseDate(movie.releaseDate)}`
        : `${movie.title} su CineFlash`;
      await Share.share({ message: what });
    } catch {}
  };

  return (
    <ModalSheet visible onClose={() => onClose()} title={movie.title}>
      <View>
        <View style={s.row}>
          <Poster uri={posterUrl(movie.posterPath, "w500")} style={st.detailPoster} />
          <View style={[s.grow, { marginLeft: 14 }]}>
            {movie.voteAverage > 0 && (
              <Badge label={`⭐ ${movie.voteAverage.toFixed(1)}/10`} tone="accent" />
            )}
            <Text style={st.detailDate}>{fmtReleaseDate(movie.releaseDate)}</Text>
            {movie.runtime ? <Text style={st.detailMeta}>{movie.runtime} min</Text> : null}
            {movie.genres && movie.genres.length > 0 ? (
              <Text style={st.detailMeta} numberOfLines={2}>
                {movie.genres.join(" · ")}
              </Text>
            ) : null}
          </View>
        </View>

        {loading && (
          <View style={[s.row, { marginTop: 12 }]}>
            <ActivityIndicator color={theme.colors.accent} size="small" />
            <Text style={st.detailMeta}> carico trailer e dettagli…</Text>
          </View>
        )}

        {/* Trailer in-app: video nativo (Apple) o embed YouTube */}
        <TrailerPlayer
          youtubeUrl={movie.trailerUrl}
          mp4Url={movie.previewUrl ?? null}
          style={st.trailer}
        />

        <Text style={st.overview}>
          {movie.overview || movie.longDescription || "Trama non disponibile."}
        </Text>

        <View style={{ marginTop: 12 }}>
          {onBook && (
            <Button
              label="🎟️  Prenota i biglietti"
              variant="primary"
              onPress={() => onBook(movie)}
            />
          )}
          {!aiDisabled && (
            <Button label="✨  Spiega con l'AI" variant="ghost" onPress={() => onOpenAI(movie)} />
          )}
          <Button
            label={
              inWatchlist
                ? "✓  Nella watchlist — tocca per rimuovere"
                : "☆  Aggiungi alla watchlist"
            }
            variant="ghost"
            onPress={() =>
              watchlist.toggle({
                id: String(movie.id),
                title: movie.title,
                posterPath: movie.posterPath,
              })
            }
          />
          {/* Promemoria uscita (solo per film non ancora usciti) */}
          {isUpcomingMovie && (
            <Button
              label={hasReminder ? "🔔 Promemoria attivo — tocca per togliere" : "🔔 Ricordami il giorno dell'uscita"}
              variant="ghost"
              onPress={toggleReminder}
              disabled={reminderBusy}
            />
          )}
          <Button label="↗  Condividi" variant="ghost" onPress={shareMovie} />
          {/* Fonte: torna all'articolo che ha citato il film */}
          {movie.articleUrl ? (
            <Button
              label={`📰  Leggi l'articolo${movie.articleSource ? ` su ${movie.articleSource}` : ""}`}
              variant="ghost"
              onPress={() => Linking.openURL(movie.articleUrl!).catch(() => {})}
            />
          ) : null}
        </View>
      </View>
    </ModalSheet>
  );
}

/** true se la data di uscita è futura (entro e non oltre 365 giorni). */
function isFutureRelease(iso: string | null | undefined): boolean {
  if (!iso) return false;
  const d = new Date(iso);
  if (isNaN(d.getTime())) return false;
  const diff = d.getTime() - Date.now();
  return diff > 0 && diff < 365 * 86_400_000;
}

const st = StyleSheet.create({
  detailPoster: { width: 96, height: 144, borderRadius: theme.radius.sm },
  detailDate: { color: theme.colors.text, fontSize: 14, fontWeight: "700", marginTop: 8 },
  detailMeta: { color: theme.colors.textDim, fontSize: 12, marginTop: 4 },
  trailer: {
    width: "100%",
    aspectRatio: 16 / 9,
    marginTop: 14,
    borderRadius: theme.radius.sm,
    backgroundColor: "#000",
  },
  overview: {
    color: theme.colors.textDim,
    fontSize: 14,
    lineHeight: 20,
    marginTop: 14,
  },
});
