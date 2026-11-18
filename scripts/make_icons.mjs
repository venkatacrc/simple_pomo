// Generates the PWA icons (pure Node, no dependencies).
//   node scripts/make_icons.mjs
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const outDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'docs', 'icons');
fs.mkdirSync(outDir, { recursive: true });

const mix = (a, b, t) => a.map((v, i) => v * (1 - t) + b[i] * t);

/** Colour at a point in normalised [0,1]² space. Returns [r,g,b,a]. */
function shade(nx, ny, { rounded, scale }) {
  if (rounded) {
    const r = 0.22;
    const dx = Math.max(Math.abs(nx - 0.5) - (0.5 - r), 0);
    const dy = Math.max(Math.abs(ny - 0.5) - (0.5 - r), 0);
    if (dx * dx + dy * dy > r * r) return [0, 0, 0, 0];
  }
  let col = mix([219, 79, 79], [169, 58, 58], ny);
  const dx = nx - 0.5, dy = ny - 0.5;
  const d = Math.hypot(dx, dy);
  const ro = 0.31 * scale, ri = 0.225 * scale;
  if (d <= ro && d >= ri) {
    let ang = Math.atan2(dx, -dy);          // 0 = top, clockwise
    if (ang < 0) ang += Math.PI * 2;
    col = mix(col, [255, 255, 255], ang <= Math.PI * 1.5 ? 1 : 0.32);
  }
  if (d <= 0.055 * scale) col = [255, 255, 255];
  return [col[0], col[1], col[2], 1];
}

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function encodePNG(w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
  ]);
}

function render(size, opts) {
  const ss = 3;
  const buf = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let sy = 0; sy < ss; sy++) {
        for (let sx = 0; sx < ss; sx++) {
          const c = shade((x + (sx + 0.5) / ss) / size, (y + (sy + 0.5) / ss) / size, opts);
          r += c[0] * c[3]; g += c[1] * c[3]; b += c[2] * c[3]; a += c[3];
        }
      }
      const i = (y * size + x) * 4;
      if (a > 0) { buf[i] = r / a; buf[i + 1] = g / a; buf[i + 2] = b / a; }
      buf[i + 3] = Math.round((a / (ss * ss)) * 255);
    }
  }
  return encodePNG(size, size, buf);
}

const files = [
  ['icon-192.png', 192, { rounded: true, scale: 1 }],
  ['icon-512.png', 512, { rounded: true, scale: 1 }],
  ['icon-maskable-512.png', 512, { rounded: false, scale: 0.78 }],
  ['apple-touch-icon.png', 180, { rounded: false, scale: 1 }],
];
for (const [name, size, opts] of files) {
  fs.writeFileSync(path.join(outDir, name), render(size, opts));
  console.log('wrote', name);
}
