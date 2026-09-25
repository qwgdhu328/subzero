/**
 * Genera gli asset grafici di CineFlash (icona, adaptive icon, splash, favicon)
 * disegnando un "film reel" dorato coerente col tema sala-proiezione.
 * Zero dipendenze: encoder PNG scritto a mano (zlib di Node).
 *
 * Uso: node scripts/gen-assets.js
 */
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

/* ---------- Canvas minimale ---------- */
class Canvas {
  constructor(w, h) {
    this.w = w;
    this.h = h;
    this.data = Buffer.alloc(w * h * 4, 0); // RGBA, trasparente
  }
  /** Composizione "source-over" con alpha 0..255. */
  blend(x, y, r, g, b, a) {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h || a <= 0) return;
    const i = (y * this.w + x) * 4;
    const sa = a / 255;
    const da = this.data[i + 3] / 255;
    const oa = sa + da * (1 - sa);
    if (oa <= 0) return;
    this.data[i] = Math.round((r * sa + this.data[i] * da * (1 - sa)) / oa);
    this.data[i + 1] = Math.round((g * sa + this.data[i + 1] * da * (1 - sa)) / oa);
    this.data[i + 2] = Math.round((b * sa + this.data[i + 2] * da * (1 - sa)) / oa);
    this.data[i + 3] = Math.round(oa * 255);
  }
  fill(color) {
    for (let y = 0; y < this.h; y++)
      for (let x = 0; x < this.w; x++) this.blend(x, y, color[0], color[1], color[2], 255);
  }
  /** Cerchio pieno anti-alias (copertura = distanza dal bordo). */
  circle(cx, cy, radius, color) {
    for (let y = Math.floor(cy - radius - 2); y <= Math.ceil(cy + radius + 2); y++) {
      for (let x = Math.floor(cx - radius - 2); x <= Math.ceil(cx + radius + 2); x++) {
        const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy);
        const cov = Math.min(1, Math.max(0, radius - d + 0.5));
        if (cov > 0) this.blend(x, y, color[0], color[1], color[2], Math.round(cov * 255));
      }
    }
  }
  /** Anello anti-alias tra due raggi. */
  ring(cx, cy, rOuter, rInner, color) {
    for (let y = Math.floor(cy - rOuter - 2); y <= Math.ceil(cy + rOuter + 2); y++) {
      for (let x = Math.floor(cx - rOuter - 2); x <= Math.ceil(cx + rOuter + 2); x++) {
        const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy);
        const covOut = Math.min(1, Math.max(0, rOuter - d + 0.5));
        const covIn = Math.min(1, Math.max(0, d - rInner + 0.5));
        const cov = Math.min(covOut, covIn);
        if (cov > 0) this.blend(x, y, color[0], color[1], color[2], Math.round(cov * 255));
      }
    }
  }
}

/* ---------- Encoder PNG ---------- */
function crc32(buf) {
  let c;
  const table = [];
  for (let n = 0; n < 256; n++) {
    c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  let crc = 0xffffffff;
  for (const b of buf) crc = table[(crc ^ b) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}
function encodePNG(canvas) {
  const { w, h, data } = canvas;
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  // filtro 0 per ogni riga
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    data.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

/* ---------- Disegno del film reel ---------- */
const GOLD = [245, 197, 24]; // #F5C518 oro marquee
const DARK = [15, 14, 19]; // #0F0E14 nero sala

/**
 * Disegna il reel (anello + 4 fori + mozzo + tacche da pellicola).
 * @param scale raggio esterno in px (la tela è 1.56× il diametro)
 */
function drawReel(size, opts) {
  const { bg = null, scale = 0.372 } = opts ?? {};
  const c = new Canvas(size, size);
  if (bg) c.fill(bg);
  const cx = size / 2;
  const cy = size / 2;
  const rOut = size * scale; // anello esterno
  const ringW = rOut * 0.185;
  const hubR = rOut * 0.34;
  const holeR = rOut * 0.21;
  const holeOrbit = rOut * 0.62;

  // tacche da pellicola lungo l'anello (micro-dettaglio, visibile su icona grande)
  const ticks = 12;
  for (let i = 0; i < ticks; i++) {
    const a = (i / ticks) * Math.PI * 2 + Math.PI / ticks;
    const tr = rOut - ringW / 2;
    c.circle(cx + Math.cos(a) * tr, cy + Math.sin(a) * tr, ringW * 0.16, DARK);
  }
  // fori del reel (scavano nel colore di fondo)
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * Math.PI * 2 + Math.PI / 4;
    c.circle(cx + Math.cos(a) * holeOrbit, cy + Math.sin(a) * holeOrbit, holeR, DARK);
  }
  c.ring(cx, cy, rOut, rOut - ringW, GOLD); // anello
  c.circle(cx, cy, hubR, GOLD); // mozzo
  c.circle(cx, cy, hubR * 0.42, DARK); // buco del mozzo
  return c;
}

const outDir = path.join(__dirname, "..", "assets");
fs.mkdirSync(outDir, { recursive: true });

const files = [
  // icona iOS/Android principale: sfondo pieno, reel grande
  { name: "icon.png", size: 1024, draw: (s) => drawReel(s, { bg: DARK, scale: 0.372 }) },
  // adaptive icon Android: foreground trasparente, reel dentro la safe zone
  { name: "adaptive-icon.png", size: 1024, draw: (s) => drawReel(s, { scale: 0.26 }) },
  // splash: logo su trasparente (il colore di sfondo lo dà il plugin)
  { name: "splash-icon.png", size: 512, draw: (s) => drawReel(s, { scale: 0.34 }) },
  { name: "favicon.png", size: 48, draw: (s) => drawReel(s, { bg: DARK, scale: 0.372 }) },
];

for (const f of files) {
  const png = encodePNG(f.draw(f.size));
  fs.writeFileSync(path.join(outDir, f.name), png);
  console.log(`✓ assets/${f.name} (${f.size}×${f.size}, ${(png.length / 1024).toFixed(1)} KB)`);
}
console.log("Fatto.");
