export interface NewsItem {
  /** id stabile per dedup: hash del link o del titolo. */
  id: string;
  title: string;
  link: string;
  /** Nome visualizzato della fonte, es. "BadTaste". */
  source: string;
  /** Chiave della sorgente (vedi DEFAULT_SOURCES). */
  sourceKey: string;
  summary: string;
  /** ISO date della pubblicazione (null se il feed non la fornisce). */
  publishedAt: string | null;
  /** URL immagine da enclosure/media:thumbnail, se presente. */
  imageUrl: string | null;
}

export interface NewsSource {
  key: string;
  name: string;
  url: string;
  enabled: boolean;
}

/** Shape minima di ciò che usa l'app (TMDB o iTunes). */
export interface Movie {
  id: number;
  title: string;
  originalTitle?: string;
  overview: string;
 /** Path TMDB (senza host) OPPURE URL assoluto (iTunes). */
  posterPath: string | null;
  /** Voto 0-10; 0 = non disponibile (es. iTunes). */
  voteAverage: number;
  releaseDate: string | null;
}

/* ---------- Raw TMDB (solo i campi che ci servono) ---------- */

export interface TmdbMovieRaw {
  id: number;
  title?: string;
  original_title?: string;
  overview?: string;
  poster_path?: string | null;
  vote_average?: number;
  release_date?: string | null;
  /** presenti negli endpoint /videos e /details */
  name?: string;
  key?: string;
  site?: string;
  type?: string;
  official?: boolean;
  published_at?: string;
}

export interface TmdbListResponse {
  page?: number;
  results?: TmdbMovieRaw[];
  total_results?: number;
}

export interface TmdbVideosResponse {
  results?: TmdbMovieRaw[];
}

export interface Settings {
  /** Chiave API TMDB (themoviedb.org, gratuita). */
  tmdbApiKey: string | null;
  /**
   * Altri feed RSS aggiunti dall'utente (oltre quelli predefiniti).
   * Include le "fonti consigliate" seminate una sola volta al primo avvio.
   */
  customSources: NewsSource[];
  /** Fonti consigliate già seminate nelle custom (true = non riprovare). */
  suggestedSeeded?: boolean;
  /** Chiavi delle sorgenti predefinite disabilitate dall'utente. */
  disabledSources: string[];
  /** Notifiche locali per nuove notizie/prevendite (default: true). */
  notifyEnabled?: boolean;
  /** Chiave del modello AI locale scelto (vedi src/logic/localAI.ts). */
  aiModelKey?: string;
  /** Disattiva l'AI locale: nasconde i pulsanti "✨ Chiedi all'AI". */
  aiDisabled?: boolean;
}
