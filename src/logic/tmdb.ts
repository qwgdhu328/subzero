import { Movie, TmdbMovieRaw, TmdbListResponse, TmdbVideosResponse } from "../models/types";

const BASE = "https://api.themoviedb.org/3";
const IMG = "https://image.tmdb.org/t/p/";

export function posterUrl(path: string | null, size: "w342" | "w500" | "w780" = "w342"): string | null {
  if (!path) return null;
  // URL già assoluto (es. da iTunes): usa quello
  if (path.startsWith("http")) return path;
  return `${IMG}${size}${path}`;
}

export function backdropUrl(path: string | null, size: "w780" | "w1280" = "w780"): string | null {
  if (!path) return null;
  if (path.startsWith("http")) return path;
  return `${IMG}${size}${path}`;
}

function toMovie(raw: TmdbMovieRaw): Movie {
  return {
    id: raw.id,
    title: raw.title ?? raw.original_title ?? "—",
    originalTitle: raw.original_title,
    overview: raw.overview ?? "",
    posterPath: raw.poster_path ?? null,
    voteAverage: raw.vote_average ?? 0,
    releaseDate: raw.release_date ?? null,
  };
}

function lang(): string {
  return "it-IT";
}

/** true se il token sembra un Read Access Token v4 (JWT), non una chiave v3. */
export function isV4Token(token: string): boolean {
  return token.startsWith("eyJ") && token.split(".").length === 3;
}

async function tmdbGet<T>(path: string, apiKey: string, query?: Record<string, string>): Promise<T> {
  const headers: Record<string, string> = { accept: "application/json" };
  const params = new URLSearchParams({
    language: lang(),
    ...query,
  });
  if (isV4Token(apiKey)) {
    // Read Access Token v4: autenticazione via header Bearer
    headers.Authorization = `Bearer ${apiKey}`;
  } else {
    // Chiave API v3: come query param
    params.set("api_key", apiKey);
  }
  const res = await fetch(`${BASE}${path}?${params.toString()}`, { headers });
  if (!res.ok) {
    throw new Error(`TMDB ${res.status}${res.status === 401 ? ": chiave API non valida" : ""}`);
  }
  return (await res.json()) as T;
}

export async function fetchNowPlaying(apiKey: string): Promise<Movie[]> {
  const data = await tmdbGet<TmdbListResponse>("/movie/now_playing", apiKey);
  return (data.results ?? []).map(toMovie);
}

export async function fetchUpcoming(apiKey: string): Promise<Movie[]> {
  const data = await tmdbGet<TmdbListResponse>("/movie/upcoming", apiKey);
  return (data.results ?? []).map(toMovie);
}

export async function fetchPopular(apiKey: string): Promise<Movie[]> {
  const data = await tmdbGet<TmdbListResponse>("/movie/popular", apiKey);
  return (data.results ?? []).map(toMovie);
}

export async function fetchMovieDetails(
  apiKey: string,
  movieId: number
): Promise<{ trailerUrl: string | null; runtime: number | null; genres: string[] }> {
  const [details, videos] = await Promise.all([
    tmdbGet<TmdbListResponse & { runtime?: number; genres?: { name: string }[] }>(
      `/movie/${movieId}`,
      apiKey
    ),
    tmdbGet<TmdbVideosResponse>(`/movie/${movieId}/videos`, apiKey),
  ]);

  const trailer = (videos.results ?? []).find(
    (v) => v.site === "YouTube" && (v.type === "Trailer" || v.type === "Teaser")
  );

  return {
    trailerUrl: trailer?.key ? `https://www.youtube.com/watch?v=${trailer.key}` : null,
    runtime: details.runtime ?? null,
    genres: (details.genres ?? []).map((g) => g.name),
  };
}

export function fmtReleaseDate(iso: string | null): string {
  if (!iso) return "data non disponibile";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return d.toLocaleDateString("it-IT", { day: "numeric", month: "long", year: "numeric" });
}
