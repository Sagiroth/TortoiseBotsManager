#!/usr/bin/env node
// tools/preview/render.js — draw the JSON scenes from scenes.lua as PNGs.
//
//   node tools/preview/render.js <scene dir> <asset dir> [scene ...]
//
// <asset dir> holds tex/ (from fetch_textures.py) and fonts/ (FRIZQT__.ttf
// and ARIALN.ttf, the client's fonts; bring your own, they are not in the
// repo). Output: <scene dir>/<scene>.png at 2x.
//
// The page resolves 1.12 anchors (SetPoint chains, two-point stretches,
// auto-sized font strings), sorts frames by strata and level and paints
// backdrops, textures and text on a canvas.

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const sceneDir = path.resolve(process.argv[2] || 'preview-out');
const assetDir = path.resolve(process.argv[3] || 'preview-assets');
const only = process.argv.slice(4);

const PAGE = String.raw`<!doctype html><html><head><meta charset="utf-8">
<style>
@font-face { font-family: FRIZ; src: url("@ASSET@/fonts/FRIZQT__.ttf"); }
@font-face { font-family: ARIALN; src: url("@ASSET@/fonts/ARIALN.ttf"); }
html,body{margin:0;background:#000}
canvas{display:block}
</style></head><body><canvas id="c"></canvas>
<script>
const ASSET = "@ASSET@";
const FONTS = {
  GameFontNormal:        { f: 'FRIZ', s: 12, c: [1, 0.82, 0] },
  GameFontNormalSmall:   { f: 'FRIZ', s: 10, c: [1, 0.82, 0] },
  GameFontNormalLarge:   { f: 'FRIZ', s: 16, c: [1, 0.82, 0] },
  GameFontNormalHuge:    { f: 'FRIZ', s: 20, c: [1, 0.82, 0] },
  GameFontHighlight:     { f: 'FRIZ', s: 12, c: [1, 1, 1] },
  GameFontHighlightSmall:{ f: 'FRIZ', s: 10, c: [1, 1, 1] },
  GameFontHighlightLarge:{ f: 'FRIZ', s: 16, c: [1, 1, 1] },
  GameFontHighlightSmallOutline:{ f: 'FRIZ', s: 10, c: [1, 1, 1], o: 1 },
  GameFontDisable:       { f: 'FRIZ', s: 12, c: [0.5, 0.5, 0.5] },
  GameFontDisableSmall:  { f: 'FRIZ', s: 10, c: [0.5, 0.5, 0.5] },
  GameFontGreen:         { f: 'FRIZ', s: 12, c: [0.1, 1, 0.1] },
  GameFontRed:           { f: 'FRIZ', s: 12, c: [1, 0.1, 0.1] },
  GameFontWhite:         { f: 'FRIZ', s: 12, c: [1, 1, 1] },
  GameTooltipText:       { f: 'FRIZ', s: 12, c: [1, 1, 1] },
  NumberFontNormal:      { f: 'ARIALN', s: 14, c: [1, 1, 1], o: 1 },
  NumberFontNormalSmall: { f: 'ARIALN', s: 12, c: [1, 1, 1], o: 1 },
  NumberFontNormalLarge: { f: 'ARIALN', s: 16, c: [1, 1, 1], o: 1 },
  ChatFontNormal:        { f: 'ARIALN', s: 14, c: [1, 1, 1] },
};
const STRATA = ['BACKGROUND','LOW','MEDIUM','HIGH','DIALOG','FULLSCREEN','FULLSCREEN_DIALOG','TOOLTIP'];
const LAYERS = ['BACKGROUND','BORDER','ARTWORK','OVERLAY','HIGHLIGHT'];

let O, byId, cv, ctx;
const imgCache = {};
function texKey(p) { return p.replace(/\\/g, '/').toLowerCase().replace(/\//g, '_') + '.png'; }
function loadImg(p) {
  const k = texKey(p);
  if (!(k in imgCache)) {
    imgCache[k] = new Promise(res => {
      const im = new Image();
      im.onload = () => res(im);
      im.onerror = () => res(null);
      im.src = ASSET + '/tex/' + k;
    });
  }
  return imgCache[k];
}

// ── text ────────────────────────────────────────────────────────────────
function fontOf(o) {
  const f = FONTS[o.font] || FONTS.GameFontNormal;
  const size = o.fontSize || f.s;
  return { css: size + 'px ' + f.f, size, color: f.c, outline: f.o };
}
// Split a 1.12 string into lines of coloured runs.
function parseRuns(text, base) {
  text = String(text || '').replace(/\|H.-?\|h/g, '').replace(/\|H[^|]*\|h/g, '').replace(/\|h/g, '')
    .replace(/\|T[^|]*\|t/g, '').replace(/\|\|/g, '|');
  const lines = [[]];
  const stack = [];
  let color = null;
  let i = 0, buf = '';
  const push = () => { if (buf) { lines[lines.length - 1].push({ t: buf, c: color }); buf = ''; } };
  while (i < text.length) {
    const ch = text[i];
    if (ch === '|' && text[i + 1] === 'c' && /^[0-9a-fA-F]{8}$/.test(text.substr(i + 2, 8))) {
      push(); const h = text.substr(i + 4, 6);
      stack.push(color);
      color = [parseInt(h.substr(0, 2), 16) / 255, parseInt(h.substr(2, 2), 16) / 255, parseInt(h.substr(4, 2), 16) / 255];
      i += 10; continue;
    }
    if (ch === '|' && text[i + 1] === 'r') { push(); color = stack.length ? stack.pop() : null; i += 2; continue; }
    if (ch === '\n') { push(); lines.push([]); i++; continue; }
    buf += ch; i++;
  }
  push();
  return lines;
}
function runsWidth(runs) { let w = 0; for (const r of runs) w += ctx.measureText(r.t).width; return w; }
// Word-wrap a line of runs to maxW.
function wrapRuns(runs, maxW) {
  if (!maxW || runsWidth(runs) <= maxW + 0.5) return [runs];
  const words = [];
  for (const r of runs) {
    const parts = r.t.split(/(\s+)/);
    for (const p of parts) if (p) words.push({ t: p, c: r.c });
  }
  const out = [];
  let cur = [], w = 0;
  for (const wd of words) {
    const ww = ctx.measureText(wd.t).width;
    if (w + ww > maxW + 0.5 && cur.length && !/^\s+$/.test(wd.t)) {
      out.push(cur); cur = []; w = 0;
    }
    if (!cur.length && /^\s+$/.test(wd.t)) continue;
    cur.push(wd); w += ww;
  }
  if (cur.length) out.push(cur);
  return out;
}
function textLayout(o, maxW) {
  const f = fontOf(o);
  ctx.font = f.css;
  const base = parseRuns(o.text, f.color);
  let lines = [];
  for (const l of base) lines = lines.concat(maxW ? wrapRuns(l, maxW) : [l]);
  let w = 0;
  for (const l of lines) w = Math.max(w, runsWidth(l));
  const lh = Math.round(f.size * 1.15);
  return { f, lines, w, lh, h: lines.length * lh };
}

// ── layout ──────────────────────────────────────────────────────────────
const H = { TOPLEFT:'L', LEFT:'L', BOTTOMLEFT:'L', TOP:'C', CENTER:'C', BOTTOM:'C', TOPRIGHT:'R', RIGHT:'R', BOTTOMRIGHT:'R' };
const V = { TOPLEFT:'T', TOP:'T', TOPRIGHT:'T', LEFT:'M', CENTER:'M', RIGHT:'M', BOTTOMLEFT:'B', BOTTOM:'B', BOTTOMRIGHT:'B' };
const rects = {};
function rectOf(o, depth) {
  if (!o) return null;
  if (rects[o.id] !== undefined) return rects[o.id];
  if ((depth || 0) > 60) return null;
  if (o.id === O.uiparent) return (rects[o.id] = { l: 0, t: 0, r: o.width, b: o.height });
  rects[o.id] = null; // cycle guard
  const pts = o.points || [];
  if (!pts.length) return null;
  const hc = {}, vc = {};
  for (const p of pts) {
    const rel = byId[p.rel] || byId[o.parent];
    const rr = rectOf(rel, (depth || 0) + 1);
    if (!rr) continue;
    const rp = p.relPoint || p.point;
    const ax = (H[rp] === 'L' ? rr.l : H[rp] === 'R' ? rr.r : (rr.l + rr.r) / 2) + (p.x || 0);
    const ay = (V[rp] === 'T' ? rr.t : V[rp] === 'B' ? rr.b : (rr.t + rr.b) / 2) - (p.y || 0);
    hc[H[p.point]] = ax; vc[V[p.point]] = ay;
  }
  let w = o.width || 0, h = o.height || 0;
  let l, r, t, b;
  if (hc.L !== undefined && hc.R !== undefined) { l = hc.L; r = hc.R; }
  if (vc.T !== undefined && vc.B !== undefined) { t = vc.T; b = vc.B; }
  if (o.kind === 'FontString' && (!w || !h)) {
    const maxW = (l !== undefined) ? (r - l) : (w || 0);
    const tl = textLayout(o, maxW);
    if (!w && l === undefined) w = Math.ceil(tl.w);
    if (!h && t === undefined) h = tl.h;
  }
  if (l === undefined) {
    if (hc.L !== undefined) { l = hc.L; r = l + w; }
    else if (hc.R !== undefined) { r = hc.R; l = r - w; }
    else if (hc.C !== undefined) { l = hc.C - w / 2; r = l + w; }
    else return null;
  }
  if (t === undefined) {
    if (vc.T !== undefined) { t = vc.T; b = t + h; }
    else if (vc.B !== undefined) { b = vc.B; t = b - h; }
    else if (vc.M !== undefined) { t = vc.M - h / 2; b = t + h; }
    else return null;
  }
  return (rects[o.id] = { l, t, r, b });
}

function visible(o) {
  let x = o;
  while (x) {
    if (x.shown === false) return false;
    if (x.id === O.uiparent) return true;
    x = byId[x.parent];
  }
  return false;
}
function strataOf(o) {
  let x = o;
  while (x) { if (x.strata) return x.strata; x = byId[x.parent]; }
  return 'MEDIUM';
}
function depthOf(o) { let n = 0, x = byId[o.parent]; while (x) { n++; x = byId[x.parent]; } return n; }
function levelOf(o) {
  if (o.level !== undefined) return o.level;
  const p = byId[o.parent];
  return p ? levelOf(p) + 1 : 0;
}
function alphaOf(o) { let a = 1, x = o; while (x) { if (x.alpha !== undefined) a *= x.alpha; x = byId[x.parent]; } return a; }

// ── paint ───────────────────────────────────────────────────────────────
function rgba(c, a) {
  return 'rgba(' + Math.round(c[0] * 255) + ',' + Math.round(c[1] * 255) + ',' + Math.round(c[2] * 255) + ',' + (a === undefined ? (c[3] === undefined ? 1 : c[3]) : a) + ')';
}
const tintCache = new Map();
function tinted(im, c) {
  if (!c || (c[0] === 1 && c[1] === 1 && c[2] === 1)) return im;
  const k = im.src + c.join(',');
  if (tintCache.has(k)) return tintCache.get(k);
  const t = document.createElement('canvas');
  t.width = im.width; t.height = im.height;
  const x = t.getContext('2d');
  x.drawImage(im, 0, 0);
  x.globalCompositeOperation = 'multiply';
  x.fillStyle = rgba(c, 1); x.fillRect(0, 0, t.width, t.height);
  x.globalCompositeOperation = 'destination-in';
  x.drawImage(im, 0, 0);
  tintCache.set(k, t);
  return t;
}
async function drawTexture(o, R, alpha) {
  const w = R.r - R.l, h = R.b - R.t;
  if (w <= 0 || h <= 0) return;
  ctx.save();
  ctx.globalAlpha = alpha * (o.vertex && o.vertex[3] !== undefined ? o.vertex[3] : 1);
  if (o.blend === 'ADD') ctx.globalCompositeOperation = 'lighter';
  if (o.color) {
    const c = o.color;
    const v = o.vertex || [1, 1, 1, 1];
    ctx.fillStyle = rgba([c[0] * v[0], c[1] * v[1], c[2] * v[2]], c[3] === undefined ? 1 : c[3]);
    ctx.fillRect(R.l, R.t, w, h);
  } else if (o.file) {
    let file = o.file, tc = o.texCoord || [0, 1, 0, 1];
    let im = await loadImg(file);
    const m = /UI-RaidTargetingIcon_(\d)$/i.exec(file);
    if (m && !im) {
      im = await loadImg('Interface\\TargetingFrame\\UI-RaidTargetingIcons');
      const i = +m[1] - 1, cx = (i % 4) * 0.25, cy = Math.floor(i / 4) * 0.25;
      tc = [cx + tc[0] * 0.25, cx + tc[1] * 0.25, cy + tc[2] * 0.25, cy + tc[3] * 0.25];
    }
    if (/white8x8$/i.test(file)) {
      const v = o.vertex || [1, 1, 1, 1];
      ctx.fillStyle = rgba(v, 1); ctx.fillRect(R.l, R.t, w, h);
    } else if (im) {
      const src = tinted(im, o.vertex);
      const sx = tc[0] * im.width, sy = tc[2] * im.height;
      const sw = (tc[1] - tc[0]) * im.width, sh = (tc[3] - tc[2]) * im.height;
      if (sw > 0 && sh > 0) ctx.drawImage(src, sx, sy, sw, sh, R.l, R.t, w, h);
    } else {
      ctx.fillStyle = 'rgba(255,0,255,0.35)'; ctx.fillRect(R.l, R.t, w, h);
    }
  }
  ctx.restore();
}
async function drawBackdrop(o, R, alpha) {
  const bd = o.backdrop; if (!bd) return;
  const ins = bd.insets || { left: 0, right: 0, top: 0, bottom: 0 };
  const bg = o.bdColor || [1, 1, 1, 1], edge = o.bdBorder || [1, 1, 1, 1];
  ctx.save(); ctx.globalAlpha = alpha;
  if (bd.bgFile) {
    const x = R.l + (ins.left || 0), y = R.t + (ins.top || 0);
    const w = R.r - R.l - (ins.left || 0) - (ins.right || 0), h = R.b - R.t - (ins.top || 0) - (ins.bottom || 0);
    if (/white8x8|tooltip-background/i.test(bd.bgFile)) {
      ctx.fillStyle = rgba(bg); ctx.fillRect(x, y, w, h);
    } else {
      const im = await loadImg(bd.bgFile);
      if (im) {
        ctx.save(); ctx.globalAlpha = alpha * (bg[3] === undefined ? 1 : bg[3]);
        const pat = ctx.createPattern(tinted(im, bg), 'repeat');
        ctx.fillStyle = pat; ctx.fillRect(x, y, w, h); ctx.restore();
      }
    }
  }
  if (bd.edgeFile) {
    const e = bd.edgeSize || 16;
    const w = R.r - R.l, h = R.b - R.t;
    if (/white8x8/i.test(bd.edgeFile)) {
      ctx.fillStyle = rgba(edge);
      ctx.fillRect(R.l, R.t, w, e); ctx.fillRect(R.l, R.b - e, w, e);
      ctx.fillRect(R.l, R.t + e, e, h - 2 * e); ctx.fillRect(R.r - e, R.t + e, e, h - 2 * e);
    } else {
      const im0 = await loadImg(bd.edgeFile);
      if (im0) {
        const im = tinted(im0, edge);
        ctx.globalAlpha = alpha * (edge[3] === undefined ? 1 : edge[3]);
        const s = im0.width / 8, sh = im0.height;
        const seg = (i, dx, dy, dw, dh, rot) => {
          if (dw <= 0 || dh <= 0) return;
          if (!rot) { ctx.drawImage(im, i * s, 0, s, sh, dx, dy, dw, dh); return; }
          ctx.save(); ctx.translate(dx, dy + dh); ctx.rotate(-Math.PI / 2);
          ctx.drawImage(im, i * s, 0, s, sh, 0, 0, dh, dw); ctx.restore();
        };
        seg(0, R.l, R.t + e, e, h - 2 * e);
        seg(1, R.r - e, R.t + e, e, h - 2 * e);
        // top/bottom strips are stored as vertical slices: rotate them.
        ctx.save(); ctx.translate(R.l + e, R.t + e); ctx.rotate(-Math.PI / 2);
        ctx.drawImage(im, 2 * s, 0, s, sh, 0, 0, e, w - 2 * e); ctx.restore();
        ctx.save(); ctx.translate(R.l + e, R.b); ctx.rotate(-Math.PI / 2);
        ctx.drawImage(im, 3 * s, 0, s, sh, 0, 0, e, w - 2 * e); ctx.restore();
        seg(4, R.l, R.t, e, e); seg(5, R.r - e, R.t, e, e);
        seg(6, R.l, R.b - e, e, e); seg(7, R.r - e, R.b - e, e, e);
      }
    }
  }
  ctx.restore();
}
function drawText(o, R, alpha, colorOverride) {
  if (!o.text) return;
  const w = R.r - R.l;
  const tl = textLayout(o, w > 0 ? w : 0);
  const f = tl.f;
  let base = colorOverride || o.textColor || f.color;
  let lines = tl.lines;
  const boxH = R.b - R.t;
  let maxLines = Math.max(1, Math.floor((boxH + 1) / tl.lh));
  if (lines.length > maxLines && o.height) {
    lines = lines.slice(0, maxLines);
    const last = lines[lines.length - 1];
    if (last.length) last[last.length - 1] = { t: last[last.length - 1].t.replace(/\s*$/, '') + '…', c: last[last.length - 1].c };
  }
  const totalH = lines.length * tl.lh;
  let y = R.t;
  if (o.justifyV === 'TOP') y = R.t;
  else if (o.justifyV === 'BOTTOM') y = R.b - totalH;
  else y = R.t + (boxH - totalH) / 2;
  ctx.save();
  ctx.globalAlpha = alpha * (base[3] === undefined ? 1 : base[3]);
  ctx.font = f.css; ctx.textBaseline = 'middle';
  for (const line of lines) {
    const lw = runsWidth(line);
    let x = R.l;
    if (o.justifyH === 'RIGHT') x = R.r - lw;
    else if (o.justifyH !== 'LEFT') x = R.l + (w - lw) / 2;
    const cy = Math.round(y + tl.lh / 2) + 0.5;
    for (const run of line) {
      const c = run.c || base;
      const rx = Math.round(x);
      if (f.outline) { ctx.strokeStyle = 'rgba(0,0,0,0.9)'; ctx.lineWidth = 2; ctx.strokeText(run.t, rx, cy); }
      ctx.fillStyle = 'rgba(0,0,0,0.85)'; ctx.fillText(run.t, rx + 1, cy + 1);
      ctx.fillStyle = rgba(c, 1); ctx.fillText(run.t, rx, cy);
      x += ctx.measureText(run.t).width;
    }
    y += tl.lh;
  }
  ctx.restore();
}

async function render(scene, cropIds) {
  O = scene; byId = {};
  for (const o of O.objects) byId[o.id] = o;
  for (const k in rects) delete rects[k];
  cv = document.getElementById('c'); ctx = cv.getContext('2d');
  await document.fonts.load('12px FRIZ'); await document.fonts.load('12px ARIALN');
  const ui = byId[O.uiparent];
  // crop to the roots (plus visible descendants that hang outside them)
  let box = null;
  const roots = (O.roots || []).map(id => byId[id]).filter(o => o && visible(o));
  const rootSet = new Set(roots.map(o => o.id));
  const underRoot = o => { let x = o; while (x) { if (rootSet.has(x.id)) return true; x = byId[x.parent]; } return false; };
  for (const o of O.objects) {
    if (!visible(o) || !underRoot(o) || o.kind === 'GameTooltip') continue;
    if (o.kind !== 'Frame' && o.kind !== 'Button' && o.kind !== 'CheckButton' && o.kind !== 'EditBox' && !rootSet.has(o.id) && !(o.backdrop)) continue;
    const r = rectOf(o); if (!r || r.r - r.l <= 0 || r.b - r.t <= 0) continue;
    if (!box) box = { ...r }; else { box.l = Math.min(box.l, r.l); box.t = Math.min(box.t, r.t); box.r = Math.max(box.r, r.r); box.b = Math.max(box.b, r.b); }
  }
  if (!box) box = { l: 0, t: 0, r: 400, b: 300 };
  const M = 14;
  box.l = Math.floor(box.l - M); box.t = Math.floor(box.t - M); box.r = Math.ceil(box.r + M); box.b = Math.ceil(box.b + M);
  const SC = 2;
  cv.width = (box.r - box.l) * SC; cv.height = (box.b - box.t) * SC;
  cv.style.width = (box.r - box.l) + 'px'; cv.style.height = (box.b - box.t) + 'px';
  ctx.setTransform(SC, 0, 0, SC, -box.l * SC, -box.t * SC);
  const g = ctx.createLinearGradient(0, box.t, 0, box.b);
  g.addColorStop(0, '#3a4a3c'); g.addColorStop(1, '#23302a');
  ctx.fillStyle = g; ctx.fillRect(box.l, box.t, box.r - box.l, box.b - box.t);

  // frames in draw order
  const frames = O.objects.filter(o => o.kind !== 'Texture' && o.kind !== 'FontString' && o.id !== O.uiparent && visible(o) && underRoot(o) && o.kind !== 'GameTooltip');
  frames.sort((a, b) => (STRATA.indexOf(strataOf(a)) - STRATA.indexOf(strataOf(b))) || (levelOf(a) - levelOf(b)) || (a.id - b.id));
  for (const fr of frames) {
    const R = rectOf(fr); if (!R) continue;
    const alpha = alphaOf(fr);
    await drawBackdrop(fr, R, alpha);
    const isBtn = fr.kind === 'Button' || fr.kind === 'CheckButton';
    const regions = O.objects.filter(o => o.parent === fr.id && (o.kind === 'Texture' || o.kind === 'FontString') && o.shown !== false);
    regions.sort((a, b) => (LAYERS.indexOf(a.layer || 'ARTWORK') - LAYERS.indexOf(b.layer || 'ARTWORK')) || (a.id - b.id));
    for (const rg of regions) {
      if (rg.layer === 'HIGHLIGHT' && !fr.lockHighlight) continue;
      if (rg.stateKey) {
        const dis = fr.enabled === false;
        if (rg.stateKey === 'pushedTex' || rg.stateKey === 'highlightTex') { if (!(rg.stateKey === 'highlightTex' && fr.lockHighlight)) continue; }
        if (rg.stateKey === 'normalTex' && dis && fr.disabledTex && byId[fr.disabledTex] && byId[fr.disabledTex].file) continue;
        if (rg.stateKey === 'disabledTex' && !dis) continue;
        if (rg.stateKey === 'checkedTex' && !fr.checked) continue;
        if (rg.stateKey === 'disabledCheckedTex') continue;
      }
      const RR = rectOf(rg); if (!RR) continue;
      const ra = alpha * (rg.alpha === undefined ? 1 : rg.alpha);
      if (rg.kind === 'Texture') await drawTexture(rg, RR, ra);
      else {
        let over = null, src = rg;
        if (isBtn && rg.isButtonText && fr.enabled === false) {
          over = fr.disabledTextColor || [0.5, 0.5, 0.5, 1];
          if (fr.disabledFont) src = Object.assign({}, rg, { font: fr.disabledFont });
        }
        drawText(src, RR, ra, over);
      }
    }
    if (fr.kind === 'EditBox' && fr.text) {
      drawText({ text: fr.text, font: fr.font || 'ChatFontNormal', justifyH: 'LEFT', textColor: fr.textColor, height: R.b - R.t }, R, alpha);
    }
    if (fr.kind === 'PlayerModel') {
      ctx.save(); ctx.fillStyle = 'rgba(255,255,255,0.06)'; ctx.fillRect(R.l, R.t, R.r - R.l, R.b - R.t);
      ctx.fillStyle = 'rgba(255,255,255,0.18)'; ctx.font = '11px FRIZ'; ctx.textAlign = 'center';
      ctx.fillText('3D model', (R.l + R.r) / 2, (R.t + R.b) / 2); ctx.restore();
    }
  }
  return { w: box.r - box.l, h: box.b - box.t };
}
window.renderScene = render;
</script></body></html>`;

(async () => {
  const files = fs.readdirSync(sceneDir).filter(f => f.endsWith('.json'))
    .filter(f => !only.length || only.includes(f.replace(/\.json$/, '')));
  const html = PAGE.split('@ASSET@').join('file://' + assetDir);
  const htmlPath = path.join(sceneDir, '_render.html');
  fs.writeFileSync(htmlPath, html);
  const browser = await chromium.launch({ args: ['--allow-file-access-from-files'] });
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  page.on('pageerror', e => console.error('page error:', e.message));
  await page.goto('file://' + htmlPath);
  for (const f of files) {
    const scene = JSON.parse(fs.readFileSync(path.join(sceneDir, f), 'utf8'));
    const size = await page.evaluate(s => window.renderScene(s), scene);
    await page.setViewportSize({ width: Math.max(200, Math.ceil(size.w)), height: Math.max(100, Math.ceil(size.h)) });
    const buf = await page.evaluate(() => document.getElementById('c').toDataURL('image/png'));
    fs.writeFileSync(path.join(sceneDir, f.replace(/\.json$/, '.png')), Buffer.from(buf.split(',')[1], 'base64'));
    console.log('rendered', f.replace(/\.json$/, ''), Math.round(size.w) + 'x' + Math.round(size.h));
  }
  await browser.close();
})();
