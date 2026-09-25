/**
 * Elenco cinema per città via OpenStreetMap Overpass API:
 * gratuito, senza chiave, CORS abilitato (funziona anche su web).
 * Da ogni cinema viene letto nome, sito ufficiale e indirizzo.
 */

export interface Cinema {
  id: string;
  name: string;
  website: string | null;
  address: string | null;
  /** Posizione (se disponibile da OSM), per ordinare per distanza. */
  lat?: number;
  lon?: number;
  /** Distanza in km dalla posizione utente (se nota). */
  distanceKm?: number;
}

const ENDPOINTS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
];

interface OverpassEl {
  type: "node" | "way" | "relation";
  id: number;
  lat?: number;
  lon?: number;
  center?: { lat: number; lon: number };
  tags?: Record<string, string>;
}

/**
 * Scarica i cinema della città scelta. cityName può essere "Milano",
 * "Roma" ecc. Restituisce anche il centro città (per ordinare per distanza
 * se in futuro si aggiunge la geolocalizzazione).
 */
export async function fetchCinemasByCity(cityName: string): Promise<Cinema[]> {
  const city = cityName.trim();
  if (!city) return [];

  const query = `
    [out:json][timeout:25];
    area["name"="${city.replace(/"/g, '\\"')}"]["boundary"="administrative"]->.a;
    (
      nwr["amenity"="cinema"](area.a);
    );
    out center tags;
  `.trim();

  let lastErr: unknown = null;
  for (const endpoint of ENDPOINTS) {
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `data=${encodeURIComponent(query)}`,
      });
      if (!res.ok) throw new Error(`Overpass ${res.status}`);
      const data = (await res.json()) as { elements?: OverpassEl[] };

      const seen = new Set<string>();
      const cinemas: Cinema[] = [];
      for (const el of data.elements ?? []) {
        const tags = el.tags ?? {};
        const name = tags.name;
        if (!name) continue;
        const key = name.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);

        const addrParts = [
          tags["addr:street"] ? tags["addr:street"] + (tags["addr:housenumber"] ? " " + tags["addr:housenumber"] : "") : null,
          tags["addr:city"] ?? null,
        ].filter(Boolean);

        const lat = el.lat ?? el.center?.lat;
        const lon = el.lon ?? el.center?.lon;
        cinemas.push({
          id: `${el.type}/${el.id}`,
          name,
          website: tags.website ?? tags["contact:website"] ?? null,
          address: addrParts.length > 0 ? addrParts.join(", ") : null,
          lat,
          lon,
        });
      }

      // Ordina per nome (la distanza si applica dopo, se c'è la posizione utente)
      cinemas.sort((a, b) => a.name.localeCompare(b.name, "it"));
      return cinemas;
    } catch (e) {
      lastErr = e;
      // prova il prossimo endpoint
    }
  }
  throw lastErr instanceof Error ? lastErr : new Error("Overpass non raggiungibile");
}

/**
 * Ordina i cinema per distanza dalla posizione utente (se disponibile)
 * e annota la distanza in km su ogni cinema. Fallisce in modo silenzioso:
 * senza permesso la lista resta per nome.
 */
export async function sortByDistance(cinemas: Cinema[]): Promise<Cinema[]> {
  try {
    const { requestForegroundPermissionsAsync, getCurrentPositionAsync, Accuracy } =
      await import("expo-location");
    const { status } = await requestForegroundPermissionsAsync();
    if (status !== "granted") return cinemas;
    const pos = await getCurrentPositionAsync({ accuracy: Accuracy.Balanced });
    const { latitude, longitude } = pos.coords;
    return cinemas
      .map((c) =>
        c.lat != null && c.lon != null
          ? { ...c, distanceKm: haversineKm(latitude, longitude, c.lat, c.lon) }
          : c
      )
      .sort((a, b) => {
        const da = a.distanceKm ?? Infinity;
        const db = b.distanceKm ?? Infinity;
        if (da !== db) return da - db;
        return a.name.localeCompare(b.name, "it");
      });
  } catch {
    return cinemas;
  }
}

/** Distanza great-circle in km tra due coordinate. */
function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

/**
 * URL del sito del cinema con ricerca del film selezionato:
 * - se il cinema ha un sito, cerca il film dentro quel dominio
 * - altrimenti Google con "nome cinema + film + biglietti"
 */
export function cinemaMovieUrl(cinema: Cinema, movieTitle: string): string {
  const q = encodeURIComponent(movieTitle);
  if (cinema.website) {
    const base = cinema.website.startsWith("http") ? cinema.website : `https://${cinema.website}`;
    // La maggior parte dei siti cinema ha una ricerca interna: site: è il
    // modo più affidabile per atterrare sulla pagina del film su quel dominio.
    return `https://www.google.com/search?q=${encodeURIComponent(
      `site:${hostOf(base)} ${movieTitle} biglietti`
    )}`;
  }
  return `https://www.google.com/search?q=${encodeURIComponent(
    `${cinema.name} ${movieTitle} biglietti`
  )}`;
}

function hostOf(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return url.replace(/^https?:\/\//, "").split("/")[0];
  }
}
