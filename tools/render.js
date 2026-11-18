// Renders the control trees recorded by tools/simulate.lua into 1920x1080 JPEGs.
//
//   node tools/render.js <screens.json> <outDir>
//
// What is exact, what is approximated:
//   * Layout is computed from the add-on's own calls (SetAnchor / SetDimensions /
//     SetAnchorFill ...) with ESO's anchor rules, on ESO's 1920x1080 UI canvas.
//   * Fonts use ESO's font table (face + pixel size from EsoUI/FontDefs, API 101051);
//     the faces themselves (Univers, Futura Condensed) are licensed, so the closest
//     free equivalents are drawn: Barlow Semi Condensed and Barlow Condensed.
//   * Colours are the ones the add-on sets; ESO's interface colours are the stock
//     values (ZO_NORMAL_TEXT C5C29E, ZO_SELECTED_TEXT FFFFFF, ZO_DISABLED_TEXT 5C5C5C).
//   * ESO's own art (backdrops, highlights, class / medal / ability icons) is not
//     redistributable, so it is drawn with close stand-ins.
//   * The gamepad keybind strip follows KEYBIND_STRIP_GAMEPAD_STYLE (ZoFontGamepad34,
//     uppercase, 96 px insets, 53 px from the bottom, 128 px background).
//   * Things ESO draws that the add-on doesn't (the native scoreboard, inventories,
//     the 3D world) are simplified stand-ins, labelled as such in the README.
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const FONTS = {
  ZoFontGame: ["Univers57", 18], ZoFontGameBold: ["Univers67", 18], ZoFontGameMedium: ["Univers57", 18],
  ZoFontGameSmall: ["Univers67", 13], ZoFontHeader: ["Univers67", 18], ZoFontWinH1: ["Univers67", 30],
  ZoFontWinH2: ["Univers67", 24], ZoFontWinH3: ["Univers67", 20], ZoFontWinH4: ["Univers67", 18],
  ZoFontGamepad18: ["FTN57", 18], ZoFontGamepad20: ["FTN57", 20], ZoFontGamepad22: ["FTN57", 22],
  ZoFontGamepad25: ["FTN57", 25], ZoFontGamepad27: ["FTN57", 27], ZoFontGamepad34: ["FTN57", 34],
  ZoFontGamepad42: ["FTN57", 42], ZoFontGamepadBold22: ["FTN87", 22], ZoFontGamepadBold27: ["FTN87", 27],
  ZoFontGamepadBold34: ["FTN87", 34], ZoFontGamepadBold42: ["FTN87", 42], ZoFontGamepadBold48: ["FTN87", 48],
  ZoFontGamepadBold54: ["FTN87", 54],
};
const FACES = {
  Univers57: ["'Barlow Semi Condensed'", 500], Univers67: ["'Barlow Semi Condensed'", 700],
  FTN47: ["'Barlow Condensed'", 300], FTN57: ["'Barlow Condensed'", 500], FTN87: ["'Barlow Condensed'", 700],
};

// Runs inside the page: resolve layout, draw.
function pageMain(screen, native, FONTS, FACES) {
  const W = screen.rootW || 1920, H = screen.rootH || 1080; // GuiRoot (SIM_GUIROOT)
  const nodes = new Map();
  const parentOf = new Map();
  (function index(list, parent) {
    for (const n of list) { nodes.set(n.id, n); if (parent) parentOf.set(n.id, parent.id); index(n.children, n); }
  })(screen.trees, null);

  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d");
  function fontOf(n) {
    const f = FONTS[n.font] || ["Univers57", 18];
    const face = FACES[f[0]];
    return { css: `${face[1]} ${f[1]}px ${face[0]}`, size: f[1], weight: face[1], family: face[0], shadow: f[0].startsWith("FTN") ? "thick" : "thin" };
  }
  const plain = t => String(t ?? "").replace(/\|c[0-9A-Fa-f]{6}/g, "").replace(/\|r/g, "").replace(/\|t[^|]*\|t/g, "MM");
  function textSize(n) {
    const f = fontOf(n);
    ctx.font = f.css;
    const lines = String(n.text ?? "").split("\n");
    let w = 0;
    for (const l of lines) w = Math.max(w, ctx.measureText(n.upper ? plain(l).toUpperCase() : plain(l)).width);
    return { w, h: lines.length * Math.round(f.size * 1.25) };
  }

  const FX = { TOPLEFT: 0, LEFT: 0, BOTTOMLEFT: 0, TOP: .5, CENTER: .5, BOTTOM: .5, TOPRIGHT: 1, RIGHT: 1, BOTTOMRIGHT: 1 };
  const FY = { TOPLEFT: 0, TOP: 0, TOPRIGHT: 0, LEFT: .5, CENTER: .5, RIGHT: .5, BOTTOMLEFT: 1, BOTTOM: 1, BOTTOMRIGHT: 1 };
  const rects = new Map();
  function rectOf(id, depth = 0) {
    if (rects.has(id)) return rects.get(id);
    const n = nodes.get(id);
    if (!n || n.kind === "root" || depth > 60) return { x: 0, y: 0, w: W, h: H };
    let w = n.w, h = n.h;
    if (n.kind === "label" && (w == null || h == null)) {
      const t = textSize(n);
      if (w == null) w = t.w;
      if (h == null) h = n.w != null ? wrappedHeight(n, n.w) : t.h;
    }
    const axis = (fr, size, key) => {
      const cons = [];
      for (const a of n.anchors) {
        const r = rectOf(a[1], depth + 1);
        const fs = fr[a[0]], fr2 = fr[a[2]];
        const c = (key === "x" ? r.x + fr2 * r.w + a[3] : r.y + fr2 * r.h + a[4]);
        cons.push([fs, c]);
      }
      if (cons.length === 2 && cons[0][0] !== cons[1][0]) {
        const [[f1, c1], [f2, c2]] = cons;
        const s = (c2 - c1) / (f2 - f1);
        return [c1 - f1 * s, s];
      }
      const s = size ?? 0;
      if (cons.length === 0) {
        const p = parentOf.has(id) ? rectOf(parentOf.get(id), depth + 1) : { x: 0, y: 0 };
        return [key === "x" ? p.x : p.y, s];
      }
      return [cons[0][1] - cons[0][0] * s, s];
    };
    const [x, ww] = axis(FX, w, "x");
    const [y, hh] = axis(FY, h, "y");
    const r = { x, y, w: ww, h: hh };
    rects.set(id, r);
    return r;
  }
  function wrappedHeight(n, width) {
    const f = fontOf(n);
    ctx.font = f.css;
    let lines = 0;
    for (const l of String(n.text ?? "").split("\n")) {
      const wl = ctx.measureText(plain(l)).width;
      lines += Math.max(1, Math.ceil(wl / Math.max(1, width)));
    }
    return lines * Math.round(f.size * 1.25);
  }

  // -------- art stand-ins --------
  const CLASS = { 1: ["D", "#e0703a"], 2: ["S", "#8f7cf0"], 3: ["N", "#d04848"], 4: ["W", "#64c08a"], 5: ["N", "#9aa4b0"], 6: ["T", "#f0d060"], 117: ["A", "#4fd0c8"] };
  const hash = s => { let h = 0; for (const c of String(s)) h = (h * 31 + c.charCodeAt(0)) >>> 0; return h; };
  // Stand-ins for ESO's battleground and UI art (the real files can't be redistributed):
  // drawn in the art's own team colours, tinted like SetColor tints a texture.
  const TEAM_HEX = { orange: ["#f0723c", "#ffb27a"], green: ["#57c26b", "#a8f0a0"], purple: ["#a77be0", "#d8c0ff"] };
  function artFor(p, r, c, a) {
    let m;
    a = a * (c[3] ?? 1); // the texture's own alpha (SetColor), as the game applies it
    const tint = `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a})`;
    const white = c[0] > .97 && c[1] > .97 && c[2] > .97;
    if ((m = p.match(/battlegrounds_teamIcon_(\w+)\.dds/))) {
      const [base, hi] = TEAM_HEX[m[1]] || TEAM_HEX.green;
      el(r, `opacity:${a}`, `<svg width="${r.w}" height="${r.h}" viewBox="0 0 64 64"><defs><linearGradient id="e${m[1]}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${hi}"/><stop offset="1" stop-color="${base}"/></linearGradient></defs><path d="M32 3l25 9v18c0 15-11 26-25 31C18 56 7 45 7 30V12z" fill="url(#e${m[1]})" stroke="#fff6dc" stroke-opacity=".85" stroke-width="2.5"/><path d="M32 14l6 12 13 2-9.5 9 2.3 13L32 44l-11.8 6 2.3-13-9.5-9 13-2z" fill="#201610" fill-opacity=".55"/></svg>`);
      return true;
    }
    if ((m = p.match(/battlegroundsCaptureBar_fill_(\w+)\.dds/))) {
      const [base, hi] = TEAM_HEX[m[1]] || TEAM_HEX.green;
      const bg = white ? `linear-gradient(180deg,${hi},${base} 55%,${base})` : `linear-gradient(180deg,rgba(255,255,255,.35),${tint})`;
      el(r, `background:${bg};opacity:${white ? a : 1};box-shadow:inset 0 1px 0 rgba(255,255,255,.45),0 0 6px ${base}66;border-radius:2px`);
      return true;
    }
    if ((m = p.match(/battlegroundsCaptureBar_point_(\w+)\.dds/))) {
      const [base, hi] = TEAM_HEX[m[1]] || TEAM_HEX.green;
      el(r, `opacity:${a}`, `<svg width="${r.w}" height="${r.h}" viewBox="0 0 40 40"><path d="M20 3l14 17-14 17L6 20z" fill="${base}" stroke="${hi}" stroke-width="2.5"/><circle cx="20" cy="20" r="5" fill="#fff6dc"/></svg>`);
      return true;
    }
    if ((m = p.match(/battlegrounds_scoreboardBG_(\w+)\.dds/))) {
      const [base] = TEAM_HEX[m[1]] || TEAM_HEX.green;
      el(r, `opacity:${a};background:linear-gradient(90deg,${base}88,${base}30 45%,rgba(10,10,12,.55));border:1px solid ${base}aa;box-shadow:inset 0 0 22px rgba(0,0,0,.55);border-radius:3px`);
      return true;
    }
    if ((m = p.match(/highlightStrip_(\w+)\.dds/))) {
      const [base] = TEAM_HEX[m[1]] || TEAM_HEX.green;
      el(r, `opacity:${a};background:linear-gradient(90deg,${base}aa,${base}33 60%,transparent);border-left:3px solid ${base}`);
      return true;
    }
    if ((m = p.match(/battleground_banner_(\w+)_(win|loss)\.dds/))) {
      const [base, hi] = TEAM_HEX[m[1]] || TEAM_HEX.green;
      const win = m[2] === "win";
      el(r, `opacity:${a};background:linear-gradient(180deg,${win ? hi : "#5a2a26"}55,${base}${win ? "40" : "22"} 40%,transparent 100%),repeating-linear-gradient(115deg,rgba(255,255,255,.035) 0 14px,transparent 14px 28px);border-top:2px solid ${win ? hi : "#c0504a"}`);
      return true;
    }
    if (/BattlegroundRoundRecapHeader/.test(p)) {
      const loss = /_loss/.test(p);
      el(r, `opacity:${a * .8}`, `<svg width="${r.w}" height="${r.h}" viewBox="0 0 720 90" preserveAspectRatio="none"><defs><linearGradient id="rh${loss ? 1 : 0}" x1="0" x2="1"><stop offset="0" stop-color="${loss ? "#a0403a" : "#d9b45a"}" stop-opacity="0"/><stop offset=".25" stop-color="${loss ? "#a0403a" : "#d9b45a"}" stop-opacity=".55"/><stop offset=".8" stop-color="${loss ? "#a0403a" : "#d9b45a"}" stop-opacity=".2"/><stop offset="1" stop-color="${loss ? "#a0403a" : "#d9b45a"}" stop-opacity="0"/></linearGradient></defs><path d="M0 12h720M0 78h720" stroke="url(#rh${loss ? 1 : 0})" stroke-width="2"/><rect x="0" y="16" width="720" height="58" fill="url(#rh${loss ? 1 : 0})" opacity=".35"/></svg>`);
      return true;
    }
    if (/lensflare_burst/.test(p)) {
      el(r, `background:radial-gradient(circle,${tint} 0%,rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a * .35}) 28%,transparent 62%)`);
      return true;
    }
    if (/progressbar_frame_bg/.test(p)) { el(r, `background:rgba(0,0,0,.55);border-radius:10px;box-shadow:inset 0 1px 3px rgba(0,0,0,.8)`); return true; }
    if (/progressbar_frame\.dds/.test(p)) { el(r, `border:2px solid rgba(197,194,158,.75);border-radius:10px;box-shadow:0 0 0 1px rgba(0,0,0,.7)`); return true; }
    const ICONS = [
      [/Icon_Experience/, '<path d="M5 4h10a4 4 0 0 1 4 4v12H9a4 4 0 0 1-4-4z" fill="#5f8f3e" stroke="#c9f0a0"/><path d="M8 8h8M8 11h8M8 14h5" stroke="#eaffd0"/>'],
      [/champion_points_health/, '<path d="M9.5 3.5h5v6h6v5h-6v6h-5v-6h-6v-5h6z" fill="#5fb06a" stroke="#d8ffd0"/>'],
      [/champion_icon/, '<path d="M12 2l2.6 6.4L21 9l-5 4.3L17.6 20 12 16.6 6.4 20 8 13.3 3 9l6.4-.6z" fill="#e8b84a" stroke="#fff1c4"/>'],
      [/achievements_reward/, '<path d="M8 2h8l-1 6H9z" fill="#b04a3a"/><circle cx="12" cy="14" r="7" fill="#d9a838" stroke="#fff1c4"/><path d="M12 10l1.4 2.8 3 .4-2.2 2.1.5 3-2.7-1.5-2.7 1.5.5-3-2.2-2.1 3-.4z" fill="#fff6dc"/>'],
      [/glyphSlot_shield/, '<path d="M12 2l8 3v6c0 5.5-3.6 9.3-8 11-4.4-1.7-8-5.5-8-11V5z" fill="#6f8fb0" stroke="#e0f0ff"/><path d="M12 6v12" stroke="#e0f0ff"/>'],
      [/currency_|currency\//i, '<circle cx="12" cy="12" r="9" fill="#3d6fb0" stroke="#cfe6ff"/><path d="M8 15l4-8 4 8M9.5 12.5h5" stroke="#fff" fill="none"/>'],
      [/battlegrounds_tabIcon_battlegrounds/, '<path d="M12 2l8 3v6c0 5.5-3.6 9.3-8 11-4.4-1.7-8-5.5-8-11V5z" fill="#3a3428" stroke="#e9d9a8"/><path d="M8 9l8 8M16 9l-8 8" stroke="#e9d9a8"/>'],
    ];
    for (const [re, d] of ICONS) if (re.test(p)) {
      el(r, `opacity:${a}`, `<svg width="${r.w}" height="${r.h}" viewBox="0 0 24 24" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`);
      return true;
    }
    return false;
  }

  function svgFor(p, w, h) {
    p = String(p || "");
    let m;
    if ((m = p.match(/class_(\d+)/))) {
      const [l, c] = CLASS[m[1]] || ["?", "#999"];
      return `<svg width="${w}" height="${h}" viewBox="0 0 44 44"><path d="M22 2l18 10v20L22 42 4 32V12z" fill="${c}" fill-opacity=".9" stroke="#fff" stroke-opacity=".45"/><text x="22" y="29" text-anchor="middle" font-family="Barlow Condensed" font-weight="700" font-size="19" fill="#111">${l}</text></svg>`;
    }
    if (/medal_/.test(p)) {
      const hue = [42, 205, 350, 130, 280, 18][hash(p) % 6];
      return `<svg width="${w}" height="${h}" viewBox="0 0 60 60"><path d="M20 2h8l4 14-6 4zM40 2h-8l-4 14 6 4z" fill="hsl(${(hue + 180) % 360} 45% 45%)"/><circle cx="30" cy="36" r="20" fill="hsl(${hue} 55% 40%)" stroke="hsl(${hue} 70% 72%)" stroke-width="2.5"/><path d="M30 25l3.2 6.6 7.2.9-5.3 5 1.4 7.2L30 41.2l-6.5 3.5 1.4-7.2-5.3-5 7.2-.9z" fill="hsl(${hue} 85% 82%)"/></svg>`;
    }
    if ((m = p.match(/battlegrounds_teamIcon_(\w+)\.dds/))) {
      const [base, hi] = TEAM_HEX[m[1]] || TEAM_HEX.green;
      return `<svg width="${w}" height="${h}" viewBox="0 0 64 64"><path d="M32 3l25 9v18c0 15-11 26-25 31C18 56 7 45 7 30V12z" fill="${base}" stroke="${hi}" stroke-width="3"/><path d="M32 14l6 12 13 2-9.5 9 2.3 13L32 44l-11.8 6 2.3-13-9.5-9 13-2z" fill="#201610" fill-opacity=".55"/></svg>`;
    }
    if (/achievements_reward/.test(p)) {
      return `<svg width="${w}" height="${h}" viewBox="0 0 24 24" stroke-width="1.4"><path d="M8 2h8l-1 6H9z" fill="#b04a3a"/><circle cx="12" cy="14" r="7" fill="#d9a838" stroke="#fff1c4"/><path d="M12 10l1.4 2.8 3 .4-2.2 2.1.5 3-2.7-1.5-2.7 1.5.5-3-2.2-2.1 3-.4z" fill="#fff6dc"/></svg>`;
    }
    if (/ability_/.test(p)) {
      const hue = hash(p) % 360;
      return `<svg width="${w}" height="${h}" viewBox="0 0 42 42"><defs><linearGradient id="g${hash(p)}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="hsl(${hue} 55% 52%)"/><stop offset="1" stop-color="#0d0f12"/></linearGradient></defs><rect x="1" y="1" width="40" height="40" fill="url(#g${hash(p)})" stroke="#c9b98a" stroke-opacity=".8" stroke-width="1.5"/><path d="M21 8l-6 13h6l-3 13 10-16h-7l3-10z" fill="#fff" fill-opacity=".85"/></svg>`;
    }
    const STAT = [
      [/deathmatch/, '<path d="M4 4l11 11M20 4L9 15M6.5 14.5l3 3M17.5 14.5l-3 3M4 20l3-3M20 20l-3-3"/>'],
      [/killingBlow/, '<path d="M12 3a7.5 7.5 0 0 0-7.5 7.5c0 2.9 1.5 4.7 3.3 5.7V20h8.4v-3.8c1.8-1 3.3-2.8 3.3-5.7A7.5 7.5 0 0 0 12 3z"/><circle cx="9.2" cy="11" r="1.4" fill="currentColor"/><circle cx="14.8" cy="11" r="1.4" fill="currentColor"/>'],
      [/bonus/, '<circle cx="8.5" cy="8" r="3"/><circle cx="16" cy="9" r="2.5"/><path d="M3 20c0-3.3 2.5-6 5.5-6s5.5 2.7 5.5 6M13.5 14.5c.8-.3 1.6-.5 2.5-.5 2.8 0 5 2.4 5 5.5"/>'],
      [/competitive/, '<path d="M12 2.5c1 3.6 5 5.4 5 10a5 5 0 0 1-10 0c0-2.4 1.3-4 2.4-5.4.3 1.8 1.3 2.8 2.4 2.9-.3-2.8-.8-4.9.2-7.5z"/>'],
      [/health/, '<path d="M9.5 3.5h5v6h6v5h-6v6h-5v-6h-6v-5h6z"/>'],
      [/scoring/, '<path d="M12 2.8l2.8 5.8 6.3.8-4.6 4.4 1.2 6.3L12 17l-5.7 3.1 1.2-6.3-4.6-4.4 6.3-.8z"/>'],
    ];
    for (const [re, d] of STAT) if (re.test(p)) {
      return `<svg width="${w}" height="${h}" viewBox="0 0 24 24" fill="none" stroke="#f2ead2" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" style="color:#f2ead2">${d}</svg>`;
    }
    return `<svg width="${w}" height="${h}"><rect width="${w}" height="${h}" fill="#444"/></svg>`;
  }
  const rgba = (c, a = 1) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${(c[3] ?? 1) * a})`;
  function markup(t) {
    let out = "", open = 0;
    const s = String(t ?? "");
    const esc = x => x.replace(/&/g, "&amp;").replace(/</g, "&lt;");
    const re = /\|c([0-9A-Fa-f]{6})|\|r|\|t([0-9.]+):([0-9.]+):([^|]*)\|t|\n/g;
    let last = 0, m;
    while ((m = re.exec(s))) {
      out += esc(s.slice(last, m.index));
      if (m[0].startsWith("|c")) { out += `<span style="color:#${m[1]}">`; open++; }
      else if (m[0] === "|r") { if (open) { out += "</span>"; open--; } }
      else if (m[0] === "\n") out += "<br>";
      else out += `<span class="ic" style="width:${m[2]}px;height:${m[3]}px">${svgFor(m[4], +m[2], +m[3])}</span>`;
      last = re.lastIndex;
    }
    out += esc(s.slice(last));
    while (open--) out += "</span>";
    return out;
  }

  // -------- draw --------
  const stage = document.getElementById("stage");
  function hiddenChain(id) {
    let cur = id;
    while (cur != null) { const n = nodes.get(cur); if (!n || n.hidden) return true; cur = parentOf.get(cur); }
    return false;
  }
  function alphaChain(id) {
    let a = 1, cur = id;
    while (cur != null) { const n = nodes.get(cur); a *= n.alpha ?? 1; cur = parentOf.get(cur); }
    return a;
  }
  // Control:SetScale: the subtree is laid out unscaled, then scaled about the
  // control's anchor point (ESO keeps the anchor fixed and scales size and children)
  let target = null;
  function el(r, css, html = "") {
    const d = document.createElement("div");
    d.style.cssText = `position:absolute;left:${r.x}px;top:${r.y}px;width:${Math.max(0, r.w)}px;height:${Math.max(0, r.h)}px;${css}`;
    d.innerHTML = html;
    (target || stage).appendChild(d);
    return d;
  }
  function draw(n) {
    if (hiddenChain(n.id)) return;
    const r = rectOf(n.id);
    const a = alphaChain(n.id);
    const c = n.color || [1, 1, 1, 1];
    if (n.kind === "backdrop") {
      const gp = n.virtual === "ZO_DefaultBackdrop_Gamepad";
      el(r, gp
        ? `background:linear-gradient(180deg,rgba(14,17,20,.86),rgba(4,5,6,.9));border:1px solid rgba(255,255,255,.16);box-shadow:inset 0 0 0 1px rgba(0,0,0,.6);opacity:${a}`
        : `background:linear-gradient(180deg,rgba(18,16,12,.93),rgba(5,5,4,.95));border:1px solid rgba(197,194,158,.32);box-shadow:inset 0 0 0 1px rgba(0,0,0,.8),0 0 0 1px rgba(0,0,0,.6);opacity:${a}`);
    } else if (n.kind === "button") {
      el(r, `display:flex;align-items:center;justify-content:center;font:700 16px 'Barlow Semi Condensed';text-transform:uppercase;letter-spacing:.04em;color:#c5c29e;background:linear-gradient(180deg,#2f2b23,#15130f);border:1px solid rgba(197,194,158,.55);box-shadow:inset 0 1px 0 rgba(255,255,255,.08);text-shadow:1px 1px 2px #000;opacity:${a}`, markup(n.text));
    } else if (n.kind === "closebutton") {
      el({ x: r.x + r.w - 18, y: r.y - 2, w: 20, h: 20 }, `color:#c5c29e;font:700 20px 'Barlow Semi Condensed';line-height:20px;text-align:center;opacity:${a}`, "×");
    } else if (n.kind === "texture") {
      const p = n.texture || "";
      const col = rgba(c, a);
      if (!p) el(r, `background:${col}`);
      else if (/listItem_selectedHighlight/.test(p)) el(r, `background:linear-gradient(90deg,rgba(255,220,130,${.55 * a}),rgba(255,210,110,${.22 * a}) 55%,rgba(255,210,110,0));box-shadow:inset 0 1px 0 rgba(255,225,150,${.5 * a}),inset 0 -1px 0 rgba(255,225,150,${.35 * a})`);
      else if (/listItem_highlight/.test(p)) el(r, `background:linear-gradient(90deg,rgba(255,255,255,${.28 * a}),rgba(255,255,255,${.12 * a}) 55%,rgba(255,255,255,0))`);
      else if (/horizontalDivider/.test(p)) el({ x: r.x, y: r.y + r.h / 2 - 1, w: r.w, h: 2 }, `background:linear-gradient(90deg,transparent,rgba(197,194,158,${.75 * a}) 20%,rgba(255,250,230,${.9 * a}) 50%,rgba(197,194,158,${.75 * a}) 80%,transparent)`);
      else if (/sortUp|sortDown/.test(p)) el(r, "", `<svg width="${r.w}" height="${r.h}" viewBox="0 0 16 16"><path d="${/sortUp/.test(p) ? "M3 11l5-6 5 6z" : "M3 5l5 6 5-6z"}" fill="${col}"/></svg>`);
      else if (artFor(p, r, c, a)) {}
      else el(r, `opacity:${a}`, svgFor(p, r.w, r.h));
    } else if (n.kind === "label" && n.text) {
      const f = fontOf(n);
      const single = n.h != null && n.h < f.size * 1.25 * 1.9;
      const shadow = f.shadow === "thick" ? "2px 2px 2px rgba(0,0,0,.95),0 0 3px rgba(0,0,0,.8)" : "1px 1px 1px rgba(0,0,0,.95)";
      const jh = { left: "flex-start", center: "center", right: "flex-end" }[n.halign] || "flex-start";
      const jv = { top: "flex-start", center: "center", bottom: "flex-end" }[n.valign] || "center";
      el(r, `display:flex;justify-content:${jh};align-items:${jv};text-align:${n.halign || "left"};overflow:hidden;color:${rgba(c, a)};font:${f.css};line-height:1.25;text-shadow:${shadow};${n.upper ? "text-transform:uppercase;" : ""}`,
        `<span style="${single ? "white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%;display:block" : ""}">${markup(n.text)}</span>`);
    }
    const scaled = n.scale != null && n.scale !== 1;
    const saved = target;
    if (scaled) {
      const a0 = n.anchors[0] || ["CENTER"];
      const px = r.x + FX[a0[0]] * r.w, py = r.y + FY[a0[0]] * r.h;
      const box = document.createElement("div");
      box.style.cssText = `position:absolute;left:0;top:0;width:${W}px;height:${H}px;transform-origin:${px}px ${py}px;transform:scale(${n.scale})`;
      (target || stage).appendChild(box);
      target = box;
    }
    for (const ch of n.children) draw(ch);
    target = saved;
  }

  // stand-ins for what ESO draws itself
  function standin(kind) {
    if (kind === "world") {
      stage.insertAdjacentHTML("beforeend", `<div style="position:absolute;inset:0;background:
        radial-gradient(ellipse at 22% 28%, rgba(255,170,90,.22), transparent 45%),
        radial-gradient(ellipse at 78% 18%, rgba(120,150,190,.18), transparent 50%),
        linear-gradient(180deg,#2c2b2f 0%,#3a3530 38%,#4a3b2c 60%,#211c17 100%);filter:blur(2px)"></div>
        <div style="position:absolute;inset:0;background:radial-gradient(ellipse at 50% 50%,transparent 45%,rgba(0,0,0,.55) 100%)"></div>`);
    } else if (kind === "nativeScoreboard") {
      const board = rectOf([...nodes.values()].find(n => n.name === "ZO_BattlegroundScoreboardTopLevelBackgrounds").id);
      const teams = (native.teams || []).slice().sort((a, b) => a.id - b.id);
      const rows = id => native.players.filter(p => p.team === id).sort((a, b) => b.s[0] - a.s[0]).slice(0, 8)
        .map(p => `<div style="display:grid;grid-template-columns:280px 180px 50px 50px 50px 1fr;gap:10px;height:24px;align-items:center;color:${p.isLocal ? "#fff" : "#c5c29e"}"><span>${p.name}</span><span></span><span>${p.s[1]}</span><span>${p.s[2]}</span><span>${p.s[3]}</span><span style="text-align:right">${p.s[0]}</span></div>`).join("");
      stage.insertAdjacentHTML("beforeend", `<div style="position:absolute;left:${board.x}px;top:${board.y}px;width:${board.w}px;height:${board.h}px;background:linear-gradient(180deg,rgba(10,9,8,.88),rgba(4,4,4,.92));border:1px solid rgba(197,194,158,.3);font:500 18px 'Barlow Semi Condensed';padding:30px 36px;box-sizing:border-box;text-shadow:1px 1px 1px #000">
        <div style="font:700 30px 'Barlow Semi Condensed';color:#fff;text-transform:uppercase;letter-spacing:.04em">${native.map}</div>
        ${teams.map(t => `<div style="margin-top:22px"><div style="display:flex;justify-content:space-between;font:700 24px 'Barlow Semi Condensed';color:#${t.color};text-transform:uppercase"><span>${t.name}</span><span>${t.score}</span></div><div style="height:2px;background:#${t.color};opacity:.6;margin:4px 0 6px"></div>${rows(t.id)}</div>`).join("")}
        <div style="position:absolute;right:16px;bottom:10px;font:500 14px 'Barlow Semi Condensed';color:#777">stand-in for ESO's battleground scoreboard</div></div>`);
    } else if (kind === "gamepadInventory") {
      const items = ["Draught of Restoration", "Spiced Venison Pie", "Grand Repair Kit", "Soul Gem", "Lockpick", "Rough Maple", "Iron Ore", "Crown Mimic Stone"];
      stage.insertAdjacentHTML("beforeend", `<div style="position:absolute;left:56px;top:0;width:470px;height:1080px;background:linear-gradient(180deg,rgba(14,17,20,.9),rgba(4,5,6,.94));padding:96px 40px 0;box-sizing:border-box;font-family:'Barlow Condensed';text-shadow:2px 2px 2px #000">
        <div style="font:700 42px 'Barlow Condensed';color:#fff;text-transform:uppercase">Inventory</div><div style="height:2px;background:rgba(255,255,255,.35);margin:10px 0 18px"></div>
        ${items.map((t, i) => `<div style="display:flex;align-items:center;gap:14px;height:52px;font:500 27px 'Barlow Condensed';color:${i === 0 ? "#fff" : "#9a9a9a"};${i === 0 ? "background:linear-gradient(90deg,rgba(255,255,255,.22),transparent)" : ""}"><span style="width:38px;height:38px;border:1px solid rgba(255,255,255,.3);background:hsl(${i * 47} 35% 35%)"></span>${t}</div>`).join("")}
        <div style="position:absolute;left:40px;bottom:150px;font:500 16px 'Barlow Condensed';color:#777">stand-in for ESO's gamepad inventory</div></div>`);
    } else if (kind === "pcInventory") {
      const inv = rectOf([...nodes.values()].find(n => n.name === "ZO_PlayerInventory").id);
      const items = [["Draught of Restoration", 40], ["Spiced Venison Pie", 22], ["Grand Repair Kit", 12], ["Soul Gem", 31], ["Lockpick", 54], ["Rough Maple", 120], ["Iron Ore", 86], ["Crown Mimic Stone", 3], ["Rubedite Ore", 214], ["Tempering Alloy", 2]];
      stage.insertAdjacentHTML("beforeend", `<div style="position:absolute;left:${inv.x}px;top:${inv.y}px;width:${inv.w}px;height:${inv.h}px;background:linear-gradient(180deg,rgba(14,12,9,.92),rgba(5,5,4,.95));border-left:1px solid rgba(197,194,158,.3);font:500 18px 'Barlow Semi Condensed';color:#c5c29e;padding:18px 22px;box-sizing:border-box;text-shadow:1px 1px 1px #000">
        <div style="font:700 30px 'Barlow Semi Condensed';color:#fff;text-transform:uppercase;letter-spacing:.04em">Inventory</div>
        <div style="height:2px;background:linear-gradient(90deg,transparent,rgba(197,194,158,.8),transparent);margin:8px 0 12px"></div>
        ${items.map(([t, n], i) => `<div style="display:flex;align-items:center;gap:12px;height:44px;${i % 2 ? "background:rgba(255,255,255,.03)" : ""}"><span style="width:34px;height:34px;border:1px solid rgba(197,194,158,.4);background:hsl(${i * 41} 30% 30%)"></span><span style="flex:1">${t}</span><span>${n}</span></div>`).join("")}
        <div style="position:absolute;left:22px;bottom:12px;font:500 14px 'Barlow Semi Condensed';color:#777">stand-in for ESO's inventory window</div></div>`);
    }
  }
  for (const s of screen.standins) standin(s);

  // ESO gamepad framework screens (UI/Console.lua): drawn from the recorded header,
  // list and tooltip state with ESO's layout and style constants
  //   quadrant 1: x 56-526, content inset 40, list text from x 197, title area 96 px
  //   quadrant 4 (GAMEPAD_RIGHT_TOOLTIP): x 1394-1864
  //   fonts: entries ZoFontGamepad34 uppercase, entry headers ZoFontGamepadBold22,
  //   header data labels ZoFontGamepad27, values ZoFontGamepadHeaderDataValue (42),
  //   tooltip title 42 uppercase, stat 27 uppercase, value 42 (small 34), body 42 light
  if (screen.console) {
    const c = screen.console;
    const H = c.header.data || {};
    const add = h => stage.insertAdjacentHTML("beforeend", h);
    const FC = "'Barlow Condensed'";
    const shadow = "text-shadow:2px 2px 2px rgba(0,0,0,.95)";
    // quadrant 1 and 4 backgrounds
    add(`<div style="position:absolute;left:0;top:0;width:566px;height:1080px;background:linear-gradient(90deg,rgba(0,0,0,.88),rgba(8,10,12,.82));border-right:2px solid rgba(255,255,255,.12)"></div>`);
    add(`<div style="position:absolute;left:1374px;top:0;width:546px;height:1080px;background:linear-gradient(270deg,rgba(0,0,0,.88),rgba(8,10,12,.8));border-left:2px solid rgba(255,255,255,.12)"></div>`);
    // header: tab bar (or title) in the 96 px title area, divider, data pairs
    const x0 = 96, w = 390;
    let y = 54;
    const tabs = H.tabBarEntries || [];
    if (tabs.length) {
      const i = (c.header.tab || 1) - 1;
      const prev = tabs[(i - 1 + tabs.length) % tabs.length].text, next = tabs[(i + 1) % tabs.length].text;
      add(`<div style="position:absolute;left:${x0}px;top:${y}px;width:${w}px;height:96px;display:flex;align-items:flex-end;justify-content:space-between;${shadow}">
        <span style="font:500 22px ${FC};color:rgba(197,194,158,.55);text-transform:uppercase">‹ ${prev}</span>
        <span style="font:500 48px ${FC};color:#fff;text-transform:uppercase;line-height:1">${tabs[i].text}</span>
        <span style="font:500 22px ${FC};color:rgba(197,194,158,.55);text-transform:uppercase">${next} ›</span></div>`);
    } else {
      add(`<div style="position:absolute;left:${x0}px;top:${y}px;width:${w}px;height:96px;display:flex;align-items:flex-end;justify-content:center;font:300 54px ${FC};color:#fff;text-transform:uppercase;${shadow}">${markup(H.titleText)}</div>`);
    }
    y += 96 + 7;
    add(`<div style="position:absolute;left:${x0}px;top:${y}px;width:${w}px;height:2px;background:rgba(255,255,255,.45)"></div>`);
    y += 14;
    for (let i = 1; i <= 4; i++) {
      if (H["data" + i + "HeaderText"] == null) continue;
      add(`<div style="position:absolute;left:${x0}px;top:${y}px;width:${w}px;height:46px;display:flex;align-items:baseline;justify-content:space-between;gap:12px;${shadow}">
        <span style="font:500 27px ${FC};color:#c5c29e;text-transform:uppercase;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${markup(H["data" + i + "HeaderText"])}</span>
        <span style="font:500 42px ${FC};color:#fff;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:62%">${markup(H["data" + i + "Text"])}</span></div>`);
      y += 46;
    }
    // parametric list: selected entry full size and white, others scaled down and dimmed
    const listTop = y + 34, listBottom = 1080 - 128 - 10;
    const rows = c.entries.map((e, i) => ({ e, i, h: (e.header ? 34 : 0) + (i + 1 === c.selected ? 64 : 50) }));
    let start = 0, used = 0;
    // keep the selection about a third of the way down, like the parametric list
    const before = rows.slice(0, c.selected - 1).reverse();
    let budget = (listBottom - listTop) * 0.35;
    start = c.selected - 1;
    for (const r of before) { if (budget - r.h < 0) break; budget -= r.h; start = r.i; }
    let yy = listTop;
    for (const r of rows.slice(start)) {
      if (yy + r.h > listBottom) break;
      const sel = r.i + 1 === c.selected;
      if (r.e.header) {
        add(`<div style="position:absolute;left:197px;top:${yy}px;width:330px;font:700 22px ${FC};color:#c5c29e;text-transform:uppercase;${shadow};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${markup(r.e.header)}</div>`);
        yy += 34;
      }
      const size = sel ? 34 : 27, icon = sel ? 52 : 40, hh = sel ? 64 : 50;
      if (r.e.icon) add(`<div style="position:absolute;left:${180 - icon}px;top:${yy + (hh - icon) / 2}px;width:${icon}px;height:${icon}px;opacity:${sel ? 1 : .55}">${svgFor(r.e.icon, icon, icon)}</div>`);
      add(`<div style="position:absolute;left:197px;top:${yy}px;width:${sel ? 360 : 320}px;height:${hh}px;display:flex;align-items:center;font:500 ${size}px ${FC};color:${sel ? "#fff" : "rgba(197,194,158,.62)"};text-transform:uppercase;${shadow}"><span style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${markup(r.e.text)}</span></div>`);
      yy += hh;
    }
    // GAMEPAD_RIGHT_TOOLTIP in quadrant 4, sized the way ZO_Tooltip sizes things:
    //   * a line or stat / value pair WITH fullWidth (widthPercent 100) gets the tooltip's
    //     width; lines wrap, and a pair's value gets width - stat - 5 and wraps
    //   * WITHOUT a width, it is as wide as its text and never wraps or truncates, so it
    //     can run past the tooltip (and the screen) edge, exactly like in game
    //   * a value is anchored 5 px after its stat (ZO_TooltipStatValuePair:SetValue);
    //     it is only right-aligned when its style says horizontalAlignment = RIGHT
    const tx = 1434, tw = 390, ttop = 70, tbottom = 1080 - 140;
    const has = (list, name) => (list || []).includes(name);
    let tip = `<div data-sbr-tip style="position:absolute;left:${tx}px;top:${ttop}px;width:${tw}px;height:${tbottom - ttop}px;clip-path:inset(0 -2000px 0 -2000px);${shadow}">`;
    for (const sec of c.tooltip) {
      tip += `<div style="margin-bottom:${sec.style === "bodyHeader" ? 18 : 30}px">`;
      for (const it of sec.items) {
        const full = has(it.styles, "fullWidth");
        if (it.kind === "pair") {
          const vs = it.valueStyle === "statValuePairValueSmall" ? 34 : 42;
          const right = has(it.valueStyles, "alignRight");
          tip += `<div data-sbr-item style="display:flex;align-items:baseline;min-height:40px;${full ? "width:100%" : "width:max-content;white-space:nowrap"}">
            <span style="font:500 27px ${FC};color:#d7d2c3;text-transform:uppercase;white-space:nowrap;flex:none">${markup(it.stat)}</span>
            <span style="margin-left:5px;font:500 ${vs}px ${FC};color:#fff;line-height:1.15;${full ? `flex:1;min-width:0;text-align:${right ? "right" : "left"};overflow-wrap:anywhere` : "white-space:nowrap"}">${markup(it.value)}</span></div>`;
        } else {
          const st = it.style;
          const css = st === "title" ? `font:500 42px ${FC};color:#fff;text-transform:uppercase;margin-bottom:8px`
            : st === "bodyHeader" ? `font:500 27px ${FC};color:#fff;text-transform:uppercase;margin-bottom:4px`
            : `font:300 42px ${FC};color:#d7d2c3`;
          tip += `<div data-sbr-item style="${css};line-height:1.15;${full ? "width:100%" : "width:max-content;white-space:nowrap"}">${markup(it.text)}</div>`;
        }
      }
      tip += `</div>`;
    }
    add(tip + `</div>`);
  }

  // add-on controls (top levels in creation order)
  for (const name of screen.draw) {
    const n = [...nodes.values()].find(x => x.name === name);
    if (n) draw(n);
  }

  // gamepad keybind strip (KEYBIND_STRIP_GAMEPAD_STYLE)
  if (screen.mode === "gamepad" && screen.strip.length) {
    const GLYPH = { PRIMARY: ["A", "#5fb94a"], NEGATIVE: ["B", "#d6453d"], SECONDARY: ["X", "#3d7fd6"], TERTIARY: ["Y", "#e1b52c"],
      LEFT_SHOULDER: ["LB"], RIGHT_SHOULDER: ["RB"], LEFT_TRIGGER: ["LT"], RIGHT_TRIGGER: ["RT"], LEFT_STICK: ["LS"], RIGHT_STICK: ["RS"], QUATERNARY: ["≡"] };
    stage.insertAdjacentHTML("beforeend", `<div style="position:absolute;left:0;right:0;bottom:0;height:128px;background:linear-gradient(180deg,rgba(0,0,0,0),rgba(0,0,0,.82) 55%)"></div>`);
    const btn = b => {
      // add-on actions that inherit a UI shortcut's key show that key's glyph
      // the native scoreboard's own actions use whatever key the player bound: a plain keycap
      const k = GLYPH[b.key.replace(/^SBR_SCOREBOARD_OPEN_/, "").replace("UI_SHORTCUT_", "")] || ["\u00a0"];
      const g = k[1] ? `<span style="display:inline-grid;place-items:center;width:40px;height:40px;border-radius:50%;background:${k[1]};color:#111;font:700 22px 'Barlow Condensed';box-shadow:inset 0 -3px 0 rgba(0,0,0,.25)">${k[0]}</span>`
        : `<span style="display:inline-grid;place-items:center;min-width:46px;height:34px;padding:0 6px;border-radius:${k[0].endsWith("S") ? "50%" : "8px"};background:#d6d2c6;color:#111;font:700 20px 'Barlow Condensed'">${k[0]}</span>`;
      return `<span style="display:inline-flex;align-items:center;gap:12px;margin-right:30px">${g}<span style="font:500 34px 'Barlow Condensed';color:#fff;text-transform:uppercase;white-space:nowrap;text-shadow:2px 2px 2px #000">${b.name}</span></span>`;
    };
    const left = screen.strip.filter(g => g.align === "left").flatMap(g => g.buttons).map(btn).join("");
    const right = screen.strip.filter(g => g.align === "right").flatMap(g => g.buttons).map(btn).join("");
    stage.insertAdjacentHTML("beforeend", `<div style="position:absolute;left:96px;bottom:33px;height:40px;display:flex;align-items:center">${left}</div>
      <div style="position:absolute;right:66px;bottom:33px;height:40px;display:flex;align-items:center">${right}</div>`);
  }
  // caption
  stage.insertAdjacentHTML("beforeend", `<div style="position:absolute;right:10px;top:8px;font:500 13px 'Barlow Semi Condensed';color:rgba(255,255,255,.45)">Simulated render · not an in-game capture</div>`);
}

(async () => {
  const [screensPath, outDir] = process.argv.slice(2);
  const data = JSON.parse(fs.readFileSync(screensPath, "utf8"));
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on("pageerror", e => errors.push(e.message));
  for (const screen of data.screens) {
    await page.setViewportSize({ width: screen.rootW || 1920, height: screen.rootH || 1080 });
    await page.setContent(`<!doctype html><html><head><meta charset="utf-8">
      <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@300;500;700&family=Barlow+Semi+Condensed:wght@500;700&display=block">
      <style>html,body{margin:0;background:#000}#stage{position:relative;width:${screen.rootW || 1920}px;height:${screen.rootH || 1080}px;overflow:hidden}.ic{display:inline-block;vertical-align:middle}.ic svg{display:block}</style>
      </head><body><div id="stage"></div></body></html>`, { waitUntil: "networkidle" });
    await page.evaluate(() => document.fonts.ready);
    await page.evaluate(([s, n, F, FA, src]) => { eval(src); pageMain(s, n, F, FA); },
      [screen, data.native, FONTS, FACES, "var pageMain = " + pageMain.toString()]);
    const file = path.join(outDir, screen.id + ".jpg");
    // anything in the tooltip that ends past the tooltip's right edge is a layout bug
    const over = await page.evaluate(() => [...document.querySelectorAll("[data-sbr-tip] [data-sbr-item], [data-sbr-tip] [data-sbr-item] > span")]
      .map(e => [e.getBoundingClientRect(), e.textContent.trim().replace(/\s+/g, " ")])
      .filter(([r]) => r.right > 1434 + 390 + 1).map(([r, t]) => `${Math.round(r.right)}px: ${t}`));
    for (const o of over) console.warn(`OVERFLOW ${screen.id}: ${o}`);
    await page.screenshot({ path: file, type: "jpeg", quality: 90 });
    console.log("wrote", file);
  }
  if (errors.length) console.log("page errors:", errors);
  await browser.close();
})();
