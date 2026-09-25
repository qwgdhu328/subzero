import { NewsItem, NewsSource } from "../models/types";

/** Retry con backoff semplice: 2 tentativi extra. */
async function fetchText(url: string, retries = 2): Promise<string> {
  let lastErr: unknown;
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const res = await fetch(url, {
        headers: {
          // alcuni feed rifiutano richieste senza User-Agent
          "User-Agent": "CineFlash/2.0 (app; usage: news reader)",
          Accept: "application/rss+xml, application/xml, text/xml, */*",
        },
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.text();
    } catch (err) {
      lastErr = err;
      if (attempt < retries) {
        await new Promise((r) => setTimeout(r, 400 * (attempt + 1)));
      }
    }
  }
  throw lastErr;
}

/* ---------- Parsing XML minimale (RSS 2.0 + Atom) ---------- */

function decodeEntities(s: string): string {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&#(\d+);/g, (_, d: string) => String.fromCharCode(Number(d)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h: string) =>
      String.fromCharCode(parseInt(h, 16))
    )
    .replace(/&amp;/g, "&");
}

/** Estrae il primo blocco <tag ...>...</tag> (gestisce CDATA). */
function firstTag(xml: string, tag: string): string | null {
  const re = new RegExp(
    `<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</${tag}>`,
    "i"
  );
  const m = re.exec(xml);
  if (!m) return null;
  return decodeEntities(m[1]).trim();
}

/** Estrae il valore di un attributo nel primo tag <tag ...>. */
function firstAttr(xml: string, tag: string, attr: string): string | null {
  const re = new RegExp(`<${tag}\\b[^>]*\\b${attr}=["']([^"']+)["'][^>]*>`, "i");
  const m = re.exec(xml);
  return m ? decodeEntities(m[1]) : null;
}

function stripHtml(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function parseDate(raw: string | null): string | null {
  if (!raw) return null;
  const d = new Date(raw);
  return isNaN(d.getTime()) ? null : d.toISOString();
}

/** id stabile per dedup: hash semplice del link (o del titolo). */
function hashId(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  }
  return `n_${(h >>> 0).toString(36)}`;
}

function parseRss(xml: string, source: NewsSource): NewsItem[] {
  const items: NewsItem[] = [];

  // RSS 2.0: <item>…</item> — Atom: <entry>…</entry>
  const itemRe = /<(item|entry)(?:\s[^>]*)?>([\s\S]*?)<\/\1>/gi;
  let m: RegExpExecArray | null;
  while ((m = itemRe.exec(xml)) !== null) {
    const block = m[2];

    const title = firstTag(block, "title");
    const linkRaw =
      firstTag(block, "link") ??
      firstAttr(block, "link", "href") ?? // atom: <link href="…"/>
      firstTag(block, "guid");
    const summaryRaw =
      firstTag(block, "description") ??
      firstTag(block, "summary") ??
      firstTag(block, "content:encoded");
    const dateRaw =
      firstTag(block, "pubDate") ??
      firstTag(block, "published") ??
      firstTag(block, "updated") ??
      firstTag(block, "dc:date");
    const img =
      firstAttr(block, "media:thumbnail", "url") ??
      firstAttr(block, "media:content", "url") ??
      firstAttr(block, "enclosure", "url") ??
      firstAttr(block, "itunes:image", "href");

    if (!title || !linkRaw) continue;

    items.push({
      id: hashId(linkRaw),
      title: stripHtml(title),
      link: linkRaw.trim(),
      source: source.name,
      sourceKey: source.key,
      summary: summaryRaw ? stripHtml(summaryRaw).slice(0, 400) : "",
      publishedAt: parseDate(dateRaw),
      imageUrl: img,
    });
  }
  return items;
}

/** Carica più feed in parallelo; i falliti vengono saltati. */
export async function fetchAllNews(
  sources: NewsSource[]
): Promise<{ items: NewsItem[]; failed: string[] }> {
  const settled = await Promise.allSettled(
    sources.map(async (src) => {
      const xml = await fetchText(src.url);
      const parsed = parseRss(xml, src);
      if (parsed.length === 0) throw new Error("feed vuoto");
      return parsed;
    })
  );

  const failed: string[] = [];
  const all: NewsItem[] = [];
  settled.forEach((r, i) => {
    if (r.status === "fulfilled") all.push(...r.value);
    else failed.push(sources[i].name);
  });

  // dedup per id + ordinamento per data (più recenti prima)
  const seen = new Set<string>();
  const deduped = all.filter((x) => {
    if (seen.has(x.id)) return false;
    seen.add(x.id);
    return true;
  });
  deduped.sort((a, b) => {
    const ta = a.publishedAt ? Date.parse(a.publishedAt) : 0;
    const tb = b.publishedAt ? Date.parse(b.publishedAt) : 0;
    return tb - ta;
  });

  return { items: deduped, failed };
}

/**
 * Scarica la pagina HTML dell'articolo ed estrae il testo pulito.
 * Usato per dare contesto reale all'AI locale (best effort, null se fallisce).
 */
export async function fetchArticleText(
  url: string,
  maxChars = 3500
): Promise<string | null> {
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": "CineFlash/2.0 (app; usage: ai context)" },
    });
    if (!res.ok) return null;
    const html = await res.text();
    const body = /<body[\s\S]*<\/body>/i.exec(html)?.[0] ?? html;
    const text = decodeEntities(
      body
        .replace(/<script[\s\S]*?<\/script>/gi, " ")
        .replace(/<style[\s\S]*?<\/style>/gi, " ")
        .replace(/<nav[\s\S]*?<\/nav>/gi, " ")
        .replace(/<header[\s\S]*?<\/header>/gi, " ")
        .replace(/<footer[\s\S]*?<\/footer>/gi, " ")
        .replace(/<form[\s\S]*?<\/form>/gi, " ")
        .replace(/<[^>]+>/g, " ")
        .replace(/&nbsp;/g, " ")
    )
      .replace(/\s+/g, " ")
      .trim();
    return text.length > 80 ? text.slice(0, maxChars) : null;
  } catch {
    return null;
  }
}

export function timeAgo(iso: string | null): string {
  if (!iso) return "";
  const diff = Date.now() - Date.parse(iso);
  if (isNaN(diff) || diff < 0) return "";
  const min = Math.floor(diff / 60_000);
  if (min < 1) return "adesso";
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `${h} ${h === 1 ? "ora" : "ore"}`;
  const d = Math.floor(h / 24);
  if (d < 7) return `${d} ${d === 1 ? "giorno" : "giorni"}`;
  return new Date(iso).toLocaleDateString("it-IT", {
    day: "numeric",
    month: "short",
  });
}
