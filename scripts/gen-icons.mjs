/**
 * Rock 家族应用图标栅格化：brand/*.svg → 工程内1024x1024 PNG
 *
 * 为什么要有这个脚本
 * ------------------
 * 2026-10-09 AGC 审核实测：「应用图标单层图尺寸为 216px*216px，标准要求 1024px*1024px」。
 * 当时工程里三张图（app_icon / foreground / background）全是 216x216 的早期占位稿。
 * `brand/` 下的 SVG 源本来就是 1024x1024 且安全区合规，所以**只需栅格化，不必重设计**。
 *
 * 之所以收进仓库而不是一次性脚本：图标是**合规关键资产**，
 * "从品牌源到上架图"的每一步都该可复现、可审计，而不是留在某台机器的 %TEMP% 里。
 *
 * 用法
 * ----
 *   npm i --no-save @resvg/resvg-js     # 仅本脚本需要，不写进 package.json
 *   node scripts/gen-icons.mjs
 *
 * 刻意**不**把 @resvg/resvg-js 写进 package.json：
 * 那份 package.json 只服务于纯逻辑单测、不参与 HAP 构建（见其 description），
 * 为一个一次性资产脚本拖进一个二进制依赖不划算。需要时临时装即可。
 *
 * 硬要求（鸿蒙分层图标规范，脚本会自动校验）
 * ------------------------------------------
 *   ① 单层图 app_icon 与分层图 foreground/background 均须 1024x1024
 *   ② 前景层**必须**含透明像素 —— 系统靠它做遮罩与视差
 *   ③ 背景层**不许**含透明像素（resvg 固定输出 RGBA，故背景层自己编码成 colorType=2）
 */

import { Resvg } from '@resvg/resvg-js';
import fs from 'fs';
import path from 'path';
import zlib from 'zlib';
import { fileURLToPath } from 'url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..');
const BRAND = path.resolve(REPO, '..', 'brand');

/** 审核要求的图标边长 */
const SIZE = 1024;

// ---------------------------------------------------------------- 纯色 PNG 编码

let CRC_TABLE = null;
function crc32(buf) {
  if (!CRC_TABLE) {
    CRC_TABLE = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      CRC_TABLE[n] = c;
    }
  }
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return c ^ -1;
}

/** 编一张纯色 PNG，colorType=2（真RGB，**没有 alpha 通道**）。用于背景层。 */
function solidPng(width, height, rgb) {
  const raw = Buffer.alloc(height * (1 + width * 3));
  for (let y = 0; y < height; y++) {
    const rowStart = y * (1 + width * 3);
    raw[rowStart] = 0; // filter = None
    for (let x = 0; x < width; x++) {
      const p = rowStart + 1 + x * 3;
      raw[p] = rgb[0];
      raw[p + 1] = rgb[1];
      raw[p + 2] = rgb[2];
    }
  }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length, 0);
    const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(td) >>> 0, 0);
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // colorType = Truecolor RGB（无 alpha）
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

// ---------------------------------------------------------------- PNG 解码（校验用）

/** 解 PNG（含完整 defilter）→ {w,h,colorType,channels,data} */
function decodePng(png) {
  let off = 8;
  let w = 0, h = 0, colorType = 0;
  const idat = [];
  while (off < png.length) {
    const len = png.readUInt32BE(off);
    const type = png.toString('ascii', off + 4, off + 8);
    const data = png.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR') {
      w = data.readUInt32BE(0);
      h = data.readUInt32BE(4);
      if (data[8] !== 8) throw new Error('只支持 8bit，实际 ' + data[8]);
      colorType = data[9];
    } else if (type === 'IDAT') {
      idat.push(data);
    }
    off += 12 + len;
  }
  let channels;
  if (colorType === 6) channels = 4;
  else if (colorType === 2) channels = 3;
  else throw new Error('colorType ' + colorType + ' 不支持');
  const stride = w * channels;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const out = Buffer.alloc(h * stride);
  let rp = 0;
  for (let y = 0; y < h; y++) {
    const filter = raw[rp++];
    const row = raw.subarray(rp, rp + stride);
    rp += stride;
    const cur = out.subarray(y * stride, (y + 1) * stride);
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : null;
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? cur[x - channels] : 0;
      const b = prev ? prev[x] : 0;
      const c = (prev && x >= channels) ? prev[x - channels] : 0;
      let v = row[x];
      if (filter === 1) v += a;
      else if (filter === 2) v += b;
      else if (filter === 3) v += (a + b) >> 1;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
      }
      cur[x] = v & 0xff;
    }
  }
  return { w, h, colorType, channels, data: out };
}

/** 数真正透明的像素（alpha < 255），而不是只看有没有 alpha 通道 */
function countTransparent(img) {
  if (img.channels !== 4) return 0;
  let n = 0;
  for (let i = 3; i < img.data.length; i += 4) if (img.data[i] !== 255) n++;
  return n;
}

// ---------------------------------------------------------------- 主流程

const MEDIA = path.join(REPO, 'AppScope', 'resources', 'base', 'media');

for (const j of [
  { src: 'rockreader.svg', out: 'app_icon.png' },
  { src: 'icon-foreground.svg', out: 'foreground.png' }
]) {
  const svg = fs.readFileSync(path.join(BRAND, j.src), 'utf8');
  const r = new Resvg(svg, { fitTo: { mode: 'width', value: SIZE }, background: 'rgba(0,0,0,0)' });
  const rendered = r.render();
  const png = rendered.asPng();
  fs.writeFileSync(path.join(MEDIA, j.out), png);
  console.log(`${j.out.padEnd(16)} ${rendered.width}x${rendered.height}  ${(png.length / 1024).toFixed(1)}KB`);
}

const bg = solidPng(SIZE, SIZE, [0, 0, 0]);
fs.writeFileSync(path.join(MEDIA, 'background.png'), bg);
console.log(`background.png   ${SIZE}x${SIZE}  ${(bg.length / 1024).toFixed(1)}KB  (colorType=2 无 alpha 通道)`);

console.log('\n--- 分层图标硬要求校验 ---');
let bad = 0;
for (const c of [
  { file: 'foreground.png', needTransparent: true },
  { file: 'background.png', needTransparent: false }
]) {
  const img = decodePng(fs.readFileSync(path.join(MEDIA, c.file)));
  const t = countTransparent(img);
  const ok = c.needTransparent ? t > 0 : (t === 0 && img.channels === 3);
  if (!ok) bad++;
  const rule = c.needTransparent ? '前景必须含透明像素（系统靠它做遮罩视差）' : '背景不许含透明像素';
  console.log(
    `${c.file.padEnd(16)} ${img.w}x${img.h} channels=${img.channels} 透明像素=${t}  [${rule}] -> ${ok ? 'OK' : '不合规'}`
  );
}
for (const f of ['app_icon.png', 'foreground.png', 'background.png']) {
  const img = decodePng(fs.readFileSync(path.join(MEDIA, f)));
  const ok = img.w === SIZE && img.h === SIZE;
  if (!ok) bad++;
  console.log(`${f.padEnd(16)} ${img.w}x${img.h} [标准 ${SIZE}x${SIZE}] -> ${ok ? 'OK' : '不合规'}`);
}
console.log(bad === 0 ? '\n全部通过' : `\n有 ${bad} 项不合规`);
process.exitCode = bad === 0 ? 0 : 1;