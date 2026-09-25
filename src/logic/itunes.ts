import { Movie } from "../models/types";

/**
 * iTunes Search API di Apple: pubblica, gratuita, NESSUNA chiave richiesta.
 * Restituisce film con poster ufficiali, trama, durata, generi e URL del
 * trailer. Limite: ~20 chiamate/minuto (abbondante per un uso personale).
 *
 * Nota: il catalogo è orientato all'iTunes Store (film acquistabili/noleggiabili):
 * ottimo per novità e uscite recenti, non è un catalogo enciclopedico come TMDB.
 */

const BASE = "https://itunes.apple.com";

export interface ParsedMovie extends Movie {
  /** Trailer ufficiale (mp4 preview di Apple). */
  previewUrl: string | null;
  longDescription: string | null;
  genres: string[];
  runtime: number | null; // minuti
  itunesUrl: string | null;
}

interface ItunesRaw {
  trackId?: number;
  trackName?: string;
  artistName?: string;
  collectionName?: string;
  artworkUrl100?: string;
  artworkUrl512?: string;
  previewUrl?: string;
  longDescription?: string;
  shortDescription?: string;
  primaryGenreName?: string;
  releaseDate?: string;
  trackViewUrl?: string;
  trackTimeMillis?: number;
  kind?: string;
}

export function toMovie(raw: ItunesRaw): ParsedMovie {
  // artworkUrl100 è scalabile: chiedo una dimensione più grande
  const poster = (raw.artworkUrl512 ?? raw.artworkUrl100 ?? "").replace(
    /\/\d+x\d+bb\./,
    "/600x600bb."
  );
  return {
    id: raw.trackId ?? 0,
    title: raw.trackName ?? "—",
    overview: raw.shortDescription ?? raw.longDescription?.slice(0, 200) ?? "",
    posterPath: poster || null, // già URL assoluto
    voteAverage: 0, // iTunes non fornisce voti
    releaseDate: raw.releaseDate ?? null,
    previewUrl: raw.previewUrl ?? null,
    longDescription: raw.longDescription ?? null,
    genres: raw.primaryGenreName ? [raw.primaryGenreName] : [],
    runtime: raw.trackTimeMillis ? Math.round(raw.trackTimeMillis / 60_000) : null,
    itunesUrl: raw.trackViewUrl ?? null,
  };
}

function parseList(data: { results?: ItunesRaw[] }): ParsedMovie[] {
  return (data.results ?? [])
    .filter((r) => r.trackName && r.artworkUrl100 && r.kind === "feature-movie")
    .map(toMovie);
}

/** Film disponibili sullo store italiano (novità in ordine di rilascio). */
export async function fetchItunesMovies(country = "it"): Promise<ParsedMovie[]> {
  const qs = new URLSearchParams({
    term: "film",
    country,
    media: "movie",
    entity: "movie",
    limit: "48",
  });
  const res = await fetch(`${BASE}/search?${qs.toString()}`);
  if (!res.ok) throw new Error(`iTunes ${res.status}`);
  return parseList((await res.json()) as { results?: ItunesRaw[] });
}

/**
 * Cerca il film citato in una notizia e restituisce il miglior match.
 * Ripulisce il titolo dalle parti editoriali ("trailer", "anticipazioni"…)
 * e prova query progressive; un match è valido solo se il titolo del
 * risultato contiene le parole principali della query.
 */
export async function findMovieFromNewsTitle(
  rawTitle: string,
  country = "it"
): Promise<ParsedMovie | null> {
  // Parole editoriali tipiche delle testate di cinema: inquinano la query
  const STOP = new Set([
    "trailer",
    "teaser",
    "ufficiale",
    "anticipazioni",
    "trama",
    "cast",
    "prevendite",
    "prevendita",
    "biglietti",
    "dal",
    "cinema",
    "video",
    "clip",
    "esclusiva",
    "anteprima",
    "primissimo",
    "primissima",
    "svelato",
  ]);

  const words = rawTitle
    .toLowerCase()
    .replace(/[^a-zàèéìòù0-9\s:]/g, " ")
    .split(/\s+/)
    .filter(
      (w) =>
        w.length >= 3 &&
        !STOP.has(w) &&
        !/^\d+$/.test(w) &&
        !/^(il|lo|la|gli|le|un|una|di|da|che|per|con|su|in|del|della|dei|delle|al|alla|ai|agli|e|ed)$/.test(w)
    );
  if (words.length === 0) return null;

  // Query progressive: 4 parole → 3 → 2 (copre titoli lunghi e corti)
  const queries: string[] = [];
  for (let len = Math.min(4, words.length); len >= 2; len--) {
    queries.push(words.slice(0, len).join(" "));
  }

  for (const q of queries) {
    try {
      const results = await searchItunesMovies(q, country);
      if (results.length === 0) continue;
      // Match valido: le parole principali della query compaiono nel titolo
      const qWords = q.split(" ");
      const hit = results.find((m) => {
        const title = m.title.toLowerCase();
        return qWords.every((w) => title.includes(w));
      });
      if (hit) return hit;
    } catch {
      // prova la query successiva
    }
  }
  return null;
}

/** Ricerca per titolo (usata anche dalla ricerca in-app). */
export async function searchItunesMovies(term: string, country = "it"): Promise<ParsedMovie[]> {
  const qs = new URLSearchParams({
    term,
    country,
    media: "movie",
    entity: "movie",
    limit: "24",
  });
  const res = await fetch(`${BASE}/search?${qs.toString()}`);
  if (!res.ok) throw new Error(`iTunes ${res.status}`);
  return parseList((await res.json()) as { results?: ItunesRaw[] });
}

/**
 * "Nuovi arrivi": feed RSS pubblico di Apple (no chiave) + lookup in blocco
 * per recuperare poster, trama e trailer di ogni titolo.
 */
export async function fetchItunesNewReleases(country = "it"): Promise<ParsedMovie[]> {
  try {
    const res = await fetch(
      `https://rss.applemarketingtools.com/api/v2/${country}/movies/top/new/all/25.json`
    );
    if (!res.ok) throw new Error(`RSS ${res.status}`);
    const data = (await res.json()) as {
      feed?: { results?: { id?: string }[] };
    };
    const ids = (data.feed?.results ?? [])
      .map((r) => r.id)
      .filter((x): x is string => Boolean(x));

    if (ids.length === 0) return [];

    const lookup = await fetch(`${BASE}/lookup?id=${ids.join(",")}&country=${country}`);
    if (!lookup.ok) throw new Error(`lookup ${lookup.status}`);
    const lookData = (await lookup.json()) as { results?: ItunesRaw[] };
    return (lookData.results ?? [])
      .filter((r) => r.trackName)
      .map(toMovie);
  } catch {
    return [];
  }
}
