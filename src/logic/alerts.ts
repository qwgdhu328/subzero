import { NewsItem } from "../models/types";

export type AlertKind = "prevendite" | "in-arrivo";

export interface NewsAlert {
  kind: AlertKind;
  label: string;
  /** Testo breve mostrato nel banner. */
  text: string;
  /** Articoli che hanno generato l'avviso, i più recenti prima. */
  items: NewsItem[];
}

/* Parole chiave (titolo + riassunto, accentate e no, case-insensitive). */
const PREVENDITE_RE =
  /\b(prevendit[ae]|bigliett[oi]\s+(?:in\s+)?(?:vendita|disponibili)|anticipazioni?|anteprima(?:\s+vendita)?|earl[xy]\s+access|oversale|primissime)\b/i;

const IN_ARRIVO_RE =
  /\b(in\s+arrivo|arriva(?:rà|no)?|esce\s+(?:il|ne[lL]la?)|uscita\s+(?:al\s+cinema|italiana|nelle\s+sale)|nelle?\s+sale|data\s+di\s+uscita|nuovo\s+film|nuova\s+pellicola|arriverà|debutta|esordisce|dal\s+\d{1,2}\s+\w+\s+al\s+cinema|trailer\s+ufficiale|teaser\s+ufficiale)\b/i;

/** true se l'articolo parla di prevendite/biglietti. */
export function isPreSale(item: NewsItem): boolean {
  const text = `${item.title} ${item.summary}`;
  return PREVENDITE_RE.test(text);
}

/** true se l'articolo annuncia un film in arrivo (uscite, trailer, annunci). */
export function isUpcoming(item: NewsItem): boolean {
  const text = `${item.title} ${item.summary}`;
  return IN_ARRIVO_RE.test(text);
}

/**
 * Costruisce gli avvisi da mostrare in cima alla tab Notizie.
 * Ordine: prevendite prima (più urgenti: i biglietti si esauriscono).
 */
export function buildAlerts(items: NewsItem[]): NewsAlert[] {
  const alerts: NewsAlert[] = [];

  const pres = items.filter(isPreSale).slice(0, 8);
  if (pres.length > 0) {
    alerts.push({
      kind: "prevendite",
      label: "🎟️ Prevendite aperte",
      text:
        pres.length === 1
          ? pres[0].title
          : `Biglietti in vendita per ${pres.length} titoli: ${pres
              .slice(0, 2)
              .map((x) => x.title)
              .join(", ")}…`,
      items: pres,
    });
  }

  const upc = items
    .filter((x) => !isPreSale(x) && isUpcoming(x))
    .slice(0, 10);
  if (upc.length > 0) {
    alerts.push({
      kind: "in-arrivo",
      label: "📅 Film in arrivo",
      text:
        upc.length === 1
          ? upc[0].title
          : `${upc.length} nuovi titoli annunciati: ${upc
              .slice(0, 2)
              .map((x) => x.title)
              .join(", ")}…`,
      items: upc,
    });
  }

  return alerts;
}
