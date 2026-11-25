"use strict";

// The DOM side of nv's web backend (nv/*_web.odin): the "nv" import module that app.wasm calls,
// and the loader that starts it (nv.start, from index.html). Like the other backends' native
// toolkits, the DOM does the work: Odin creates elements, styles them and appends them, and CSS
// (nv.css) lays them out. Elements travel to Odin as small integer ids (nv.View) into `els`; the
// creator releases an id, which also takes the element out of the document. Events come back
// through the wasm's exports (nv_web_*), which restore the Odin context and bracket the callback.
// The Odin runtime's own imports (odin_env: stdout, time, math) come from odin.js, copied from the
// compiler that built app.wasm.
(function () {

// Web_Event in web.odin.
const EV = {
	BUTTON: 0, INPUT_CHANGE: 1, INPUT_SUBMIT: 2, ACTION: 3, BACK: 4, MENU: 5, FAB: 6, SCRIM: 7,
	TAB: 8, LIST_SELECT: 9, THEME: 10,
};

let mem = null; // odin.WasmMemoryInterface
let ex = null;  // the wasm's exports
const enc = new TextEncoder();
const S = (p, n) => mem.loadString(p, n);

// ---- elements ----

const els = [null]; // id -> element; 0 is nil
const freeIds = [];

function put(el) {
	const id = freeIds.length > 0 ? freeIds.pop() : els.length;
	els[id] = el;
	return id;
}

function release(id) {
	const el = els[id];
	if (!el) return;
	if (el.nvCanvas) canvasDispose(el.nvCanvas);
	if (el.nvList) listDispose(el.nvList);
	el.remove();
	els[id] = null;
	freeIds.push(id);
}

const css = (argb) => {
	argb >>>= 0;
	return `rgba(${(argb >>> 16) & 255}, ${(argb >>> 8) & 255}, ${argb & 255}, ${((argb >>> 24) / 255).toFixed(3)})`;
};

// Material icons (Apache 2.0), by nv.Icon; 16 is the back arrow.
const ICONS = [
	"",
	"M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z",
	"M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z",
	"M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z",
	"M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z",
	"M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11A2.99 2.99 0 0 0 21 5a3 3 0 1 0-5.91.7L8.04 9.81A2.99 2.99 0 0 0 3 12a3 3 0 0 0 5.04 2.19l7.12 4.16c-.05.21-.08.43-.08.65a2.92 2.92 0 1 0 2.92-2.92z",
	"M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.48.48 0 0 0-.48-.41h-3.84a.47.47 0 0 0-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.48.48 0 0 0-.59.22L2.74 8.87a.47.47 0 0 0 .12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32a.48.48 0 0 0-.12-.61l-2.01-1.58zM12 15.6a3.6 3.6 0 1 1 0-7.2 3.6 3.6 0 0 1 0 7.2z",
	"M17.65 6.35A7.96 7.96 0 0 0 12 4a8 8 0 1 0 7.73 10h-2.08A6 6 0 1 1 12 6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z",
	"M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z",
	"M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z",
	"M12 8a2 2 0 1 0 0-4 2 2 0 0 0 0 4zm0 2a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm0 6a2 2 0 1 0 0 4 2 2 0 0 0 0-4z",
	"M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z",
	"M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z",
	"M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z",
	"M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z",
	"M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z",
	"M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z",
];

function iconSvg(i) {
	const NS = "http://www.w3.org/2000/svg";
	const svg = document.createElementNS(NS, "svg");
	svg.setAttribute("viewBox", "0 0 24 24");
	svg.setAttribute("aria-hidden", "true");
	const path = document.createElementNS(NS, "path");
	path.setAttribute("d", ICONS[i] || "");
	svg.append(path);
	return svg;
}

function event(kind, h, arg) {
	ex.nv_web_event(kind, h, arg);
}

// ---- history: the browser's Back pops a page ----

// `hcur` is the history entry nv believes is current ({nv: depth}); `hexpect` counts the popstate
// events of nv's own history.go, which are not the user's.
let hcur = 0, hexpect = 0;

function historySync(depth) {
	if (depth > hcur) {
		while (hcur < depth) history.pushState({nv: ++hcur}, "");
	} else if (depth < hcur) {
		hexpect++;
		const n = depth - hcur;
		hcur = depth;
		history.go(n);
	}
}

function onPopState(e) {
	if (hexpect > 0) { hexpect--; return; }
	const d = e.state && typeof e.state.nv === "number" ? e.state.nv : 0;
	hcur = d;
	// One Back per entry left behind; a Back that pops nothing (a modal dialog, an open drawer)
	// stops it, and the entries are put back to match the stack.
	for (let depth = ex.nv_web_depth(); depth > d; ) {
		event(EV.BACK, 0, 0);
		const after = ex.nv_web_depth();
		if (after >= depth) break;
		depth = after;
	}
	historySync(ex.nv_web_depth());
}

// ---- lists: a virtualized scroller with recycled rows ----

const resizeObserver = new ResizeObserver((entries) => {
	for (const e of entries) {
		const t = e.target;
		if (t.nvList) listRender(t.nvList);
		if (t.nvCanvas) canvasResized(t.nvCanvas, e);
	}
});

function listCreate(h, rowH) {
	const root = document.createElement("div");
	root.className = "nv-list";
	const spacer = document.createElement("div");
	spacer.className = "nv-list-spacer";
	root.append(spacer);
	const l = {h, root, spacer, rowH, count: 0, sel: -1, shown: new Map(), pool: [], alive: true};
	root.nvList = l;
	root.addEventListener("scroll", () => listRender(l), {passive: true});
	root.addEventListener("click", (e) => {
		const cell = e.target.closest(".nv-cell");
		if (!cell || !root.contains(cell)) return;
		const i = Number(cell.dataset.i);
		listSelect(l, i);
		event(EV.LIST_SELECT, l.h, i);
	});
	resizeObserver.observe(root);
	return put(root);
}

function listDispose(l) {
	l.alive = false;
	resizeObserver.unobserve(l.root);
	for (const c of [...l.shown.values(), ...l.pool]) { els[c.title] = null; els[c.sub] = null; freeIds.push(c.title, c.sub); }
	l.shown.clear();
	l.pool = [];
}

function listSelect(l, i) {
	l.sel = i;
	for (const [j, c] of l.shown) c.el.classList.toggle("nv-selected", j === i);
}

function listCount(l, n) {
	l.count = n;
	l.spacer.style.height = `${n * l.rowH}px`;
	if (l.sel >= n) l.sel = -1;
	for (const c of l.shown.values()) { c.el.remove(); l.pool.push(c); }
	l.shown.clear();
	listRender(l);
}

function listRender(l) {
	if (!l.alive) return;
	const top = l.root.scrollTop, height = l.root.clientHeight;
	const first = Math.max(0, Math.floor(top / l.rowH) - 2);
	const end = Math.min(l.count, Math.ceil((top + height) / l.rowH) + 2);
	for (const [i, c] of l.shown) {
		if (i < first || i >= end) { c.el.remove(); l.shown.delete(i); l.pool.push(c); }
	}
	for (let i = first; i < end; i++) {
		if (l.shown.has(i)) continue;
		let c = l.pool.pop();
		const fresh = !c;
		if (fresh) {
			const el = document.createElement("div");
			el.className = "nv-cell";
			el.style.height = `${l.rowH}px`;
			const t = document.createElement("div"), s = document.createElement("div");
			t.className = "nv-cell-title";
			s.className = "nv-cell-sub";
			el.append(t, s);
			c = {el, title: put(t), sub: put(s)};
		}
		c.el.dataset.i = i;
		c.el.style.transform = `translateY(${i * l.rowH}px)`;
		c.el.classList.toggle("nv-selected", i === l.sel);
		l.root.append(c.el);
		l.shown.set(i, c);
		ex.nv_web_list_bind(l.h, i, c.title, c.sub, fresh);
	}
}

// ---- canvases ----

const canvases = new Set();
let cur = null; // the canvas being drawn: the draw imports paint on cur.ctx

function canvasCreate(h) {
	const wrap = document.createElement("div");
	wrap.className = "nv-canvas";
	const c = document.createElement("canvas");
	wrap.append(c);
	const s = {h, wrap, c, ctx: c.getContext("2d"), w: 0, ht: 0, dpr: 1, queued: false, stale: false, alive: true, down: false, ascent: new Map()};
	wrap.nvCanvas = s;
	canvases.add(s);
	resizeObserver.observe(wrap);
	const pos = (e) => { const r = c.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
	c.addEventListener("pointerdown", (e) => {
		if (e.button !== 0) return;
		s.down = true;
		c.setPointerCapture(e.pointerId);
		ex.nv_web_pointer(s.h, 0, ...pos(e));
	});
	c.addEventListener("pointermove", (e) => { if (s.down) ex.nv_web_pointer(s.h, 1, ...pos(e)); });
	const up = (e) => { if (!s.down) return; s.down = false; ex.nv_web_pointer(s.h, 2, ...pos(e)); };
	c.addEventListener("pointerup", up);
	c.addEventListener("pointercancel", up);
	return put(wrap);
}

function canvasDispose(s) {
	s.alive = false;
	canvases.delete(s);
	resizeObserver.unobserve(s.wrap);
}

function canvasResized(s) {
	s.w = s.wrap.clientWidth;
	s.ht = s.wrap.clientHeight;
	canvasDraw(s); // at once, so a resize never shows a stretched frame
}

function canvasRedraw(s) {
	if (s.queued || !s.alive) return;
	s.queued = true;
	requestAnimationFrame(() => { s.queued = false; canvasDraw(s); });
}

// A canvas on a page below the top, in a hidden tab or a hidden view is not drawn (so a spinning
// Progress stops by itself, as on the other platforms); it is drawn once it shows again.
function canvasDraw(s) {
	if (!s.alive) return;
	if (!s.wrap.isConnected || !s.wrap.checkVisibility() || s.w <= 0 || s.ht <= 0) { s.stale = true; return; }
	s.stale = false;
	const dpr = window.devicePixelRatio || 1;
	const bw = Math.round(s.w * dpr), bh = Math.round(s.ht * dpr);
	if (s.c.width !== bw || s.c.height !== bh) { s.c.width = bw; s.c.height = bh; }
	const ctx = s.ctx;
	ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
	ctx.clearRect(0, 0, s.w, s.ht);
	s.fill = s.stroke = s.font = s.lw = undefined; // what the context was last set to
	cur = s;
	try { ex.nv_web_draw(s.h, s.w, s.ht); } finally { cur = null; }
}

function redrawStale() {
	for (const s of canvases) if (s.stale) canvasRedraw(s);
}

function redrawAll() {
	for (const s of canvases) canvasRedraw(s);
}

function fillStyle(argb) {
	if (cur.fill !== argb) { cur.fill = argb; cur.ctx.fillStyle = css(argb); }
	return cur.ctx;
}

function strokeStyle(argb, width, cap) {
	const ctx = cur.ctx;
	if (cur.stroke !== argb) { cur.stroke = argb; ctx.strokeStyle = css(argb); }
	if (cur.lw !== width) { cur.lw = width; ctx.lineWidth = width; }
	ctx.lineCap = cap;
	ctx.beginPath();
	return ctx;
}

const SYSTEM_FONT = 'system-ui, -apple-system, "Segoe UI", Roboto, sans-serif';

// ---- bitmaps and fonts ----

// A bitmap is decoded off the main thread (createImageBitmap) for the canvas and shown through a
// blob URL by <img>; Odin already knows its size from the header (imagesize.odin).
const bitmaps = [null];
const fonts = [null];

function bitmapCreate(bytes) {
	const b = {blob: new Blob([bytes]), image: null, url: null, alive: true};
	createImageBitmap(b.blob).then((img) => {
		if (!b.alive) { img.close(); return; }
		b.image = img;
		redrawAll();
	}, () => {});
	bitmaps.push(b);
	return bitmaps.length - 1;
}

// ---- assets and downloads ----

const assets = new Map(); // path under app/assets -> bytes, all loaded before the app starts

function deliver(f, bytes) {
	if (!ex) return;
	if (!bytes) { ex.nv_web_fetched(f, 0, -1); return; }
	const p = ex.nv_web_alloc(bytes.length);
	mem.loadBytes(p, bytes.length).set(bytes);
	ex.nv_web_fetched(f, p, bytes.length);
}

// ---- theme ----

const darkQuery = window.matchMedia("(prefers-color-scheme: dark)");

function systemAccent() {
	if (!CSS.supports("color", "AccentColor")) return 0;
	const probe = document.createElement("div");
	probe.style.color = "AccentColor";
	document.body.append(probe);
	const m = getComputedStyle(probe).color.match(/[\d.]+/g);
	probe.remove();
	if (!m || m.length < 3) return 0;
	const a = m.length > 3 ? Math.round(Number(m[3]) * 255) : 255;
	return ((a << 24) | (Number(m[0]) << 16) | (Number(m[1]) << 8) | Number(m[2])) >>> 0;
}

// ---- the import module ----

const imports = {
	js_app: () => put(document.getElementById("nv-app")),
	js_create: (tp, tn, cp, cn) => {
		const el = document.createElement(S(tp, tn));
		const c = S(cp, cn);
		if (c) el.className = c;
		return put(el);
	},
	js_release: release,
	js_append: (p, c) => els[p].append(els[c]),
	js_clear: (id) => els[id].replaceChildren(),
	// A label is a box centering one line of text, which is cut with an ellipsis (nv.css).
	js_label: (cp, cn) => {
		const el = document.createElement("div");
		el.className = S(cp, cn);
		el.nvText = document.createElement("span");
		el.append(el.nvText);
		return put(el);
	},
	js_text: (id, p, n) => { (els[id].nvText || els[id]).textContent = S(p, n); },
	js_style: (id, kp, kn, vp, vn) => els[id].style.setProperty(S(kp, kn), S(vp, vn)),
	js_attr: (id, kp, kn, vp, vn) => els[id].setAttribute(S(kp, kn), S(vp, vn)),
	js_class: (id, cp, cn, on) => els[id].classList.toggle(S(cp, cn), !!on),
	js_hidden: (id, on) => {
		els[id].classList.toggle("nv-hidden", !!on);
		if (!on) redrawStale();
	},
	js_inert: (id, on) => { els[id].inert = !!on; },
	js_focus: (id) => els[id].focus(),
	js_blur: () => { if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); },
	js_icon: (id, icon) => els[id].append(iconSvg(icon)),
	js_listen: (id, kind, h, arg) => {
		const el = els[id];
		if (kind === EV.INPUT_CHANGE) {
			el.addEventListener("input", () => event(kind, h, arg));
		} else if (kind === EV.INPUT_SUBMIT) {
			el.addEventListener("keydown", (e) => {
				if (e.key === "Enter" && !e.isComposing) { e.preventDefault(); event(kind, h, arg); }
			});
		} else {
			el.addEventListener("click", () => event(kind, h, arg));
		}
	},
	js_value: (id, bp, bn) => {
		const b = enc.encode(els[id].value);
		if (b.length <= bn) mem.loadBytes(bp, b.length).set(b);
		return b.length;
	},
	js_set_value: (id, p, n) => { els[id].value = S(p, n); },
	js_title: (p, n) => { document.title = S(p, n); },
	js_root_style: (kp, kn, vp, vn) => document.documentElement.style.setProperty(S(kp, kn), S(vp, vn)),
	js_history: historySync,
	js_show_page: () => redrawStale(),

	js_list_create: listCreate,
	js_list_count: (id, n) => listCount(els[id].nvList, n),

	js_canvas_create: canvasCreate,
	js_canvas_redraw: (id) => canvasRedraw(els[id].nvCanvas),
	js_fill_rect: (x, y, w, h, c) => fillStyle(c).fillRect(x, y, w, h),
	js_stroke_rect: (x, y, w, h, c, lw) => {
		const ctx = strokeStyle(c, lw, "butt");
		ctx.lineJoin = "miter";
		ctx.strokeRect(x, y, w, h);
	},
	js_line: (x0, y0, x1, y1, c, lw) => {
		const ctx = strokeStyle(c, lw, "round");
		ctx.moveTo(x0, y0);
		ctx.lineTo(x1, y1);
		ctx.stroke();
	},
	js_fill_ellipse: (x, y, w, h, c) => {
		const ctx = fillStyle(c);
		ctx.beginPath();
		ctx.ellipse(x + w / 2, y + h / 2, Math.abs(w / 2), Math.abs(h / 2), 0, 0, 2 * Math.PI);
		ctx.fill();
	},
	js_stroke_ellipse: (x, y, w, h, c, lw) => {
		const ctx = strokeStyle(c, lw, "butt");
		ctx.ellipse(x + w / 2, y + h / 2, Math.abs(w / 2), Math.abs(h / 2), 0, 0, 2 * Math.PI);
		ctx.stroke();
	},
	js_arc: (cx, cy, r, start, sweep, c, lw) => {
		const ctx = strokeStyle(c, lw, "butt");
		const a0 = start * Math.PI / 180;
		ctx.arc(cx, cy, r, a0, a0 + sweep * Math.PI / 180, sweep < 0);
		ctx.stroke();
	},
	// (x, y) is the top-left of the line box: the baseline is the font's ascent below it.
	js_draw_text: (p, n, x, y, size, weight, italic, font, c) => {
		const ctx = fillStyle(c);
		const family = font ? `"nv-font-${font}", ${SYSTEM_FONT}` : SYSTEM_FONT;
		const f = `${italic ? "italic " : ""}${weight} ${size}px ${family}`;
		if (cur.font !== f) { cur.font = f; ctx.font = f; }
		let ascent = cur.ascent.get(f);
		if (ascent === undefined) {
			ascent = ctx.measureText("Hg").fontBoundingBoxAscent;
			cur.ascent.set(f, ascent);
		}
		ctx.textBaseline = "alphabetic";
		ctx.fillText(S(p, n), x, y + ascent);
	},
	js_draw_image: (id, x, y, w, h) => {
		const b = bitmaps[id];
		if (!b || !b.image) return; // still decoding: every canvas redraws once it is done
		cur.ctx.imageSmoothingQuality = "high";
		cur.ctx.drawImage(b.image, x, y, w, h);
	},

	js_bitmap: (p, n) => bitmapCreate(mem.loadBytes(p, n).slice()),
	js_bitmap_release: (id) => {
		const b = bitmaps[id];
		if (!b) return;
		b.alive = false;
		if (b.image) b.image.close();
		if (b.url) URL.revokeObjectURL(b.url);
		bitmaps[id] = null;
	},
	js_image_set: (id, bmp, fit) => {
		const img = els[id];
		const b = bitmaps[bmp];
		img.style.objectFit = ["contain", "cover", "fill"][fit] || "contain";
		if (!b) { img.removeAttribute("src"); img.classList.add("nv-hidden"); return; }
		if (!b.url) b.url = URL.createObjectURL(b.blob);
		img.src = b.url;
		img.classList.remove("nv-hidden");
	},

	js_font: (p, n, weight, italic) => {
		const id = fonts.length;
		let face;
		try {
			face = new FontFace(`nv-font-${id}`, mem.loadBytes(p, n).slice(), {weight: String(weight), style: italic ? "italic" : "normal"});
		} catch (e) {
			return 0;
		}
		fonts.push(face);
		document.fonts.add(face);
		face.load().then(() => { for (const s of canvases) s.ascent.clear(); redrawAll(); }, () => {});
		return id;
	},
	js_font_release: (id) => {
		if (fonts[id]) document.fonts.delete(fonts[id]);
		fonts[id] = null;
	},

	js_asset_size: (p, n) => {
		const a = assets.get(S(p, n));
		return a ? a.length : -1;
	},
	js_asset_copy: (p, n, bp, bn) => {
		const a = assets.get(S(p, n));
		if (a && a.length <= bn) mem.loadBytes(bp, a.length).set(a);
	},
	js_fetch: (p, n, f) => {
		fetch(S(p, n))
			.then((r) => (r.ok ? r.arrayBuffer() : null))
			.then((b) => deliver(f, b ? new Uint8Array(b) : null), () => deliver(f, null));
	},
	js_timeout: (ms, t) => { setTimeout(() => ex.nv_web_timer(t), ms); },

	js_system_dark: () => darkQuery.matches,
	js_system_accent: systemAccent,
	js_color_scheme: (dark) => { document.documentElement.style.colorScheme = dark ? "dark" : "light"; },
	js_redraw_all: redrawAll,
};

// ---- the loader ----

// Debug builds send the app's stdout and uncaught errors to nvbuild's dev server too
// (POST /__nv/log), so they show in the terminal that ran the build, in order.
let logChain = Promise.resolve();
let logLine = "";

function devLog(text) {
	logLine += text;
	const nl = logLine.lastIndexOf("\n");
	if (nl < 0) return;
	const body = logLine.slice(0, nl + 1);
	logLine = logLine.slice(nl + 1);
	logChain = logChain.then(() => fetch("/__nv/log", {method: "POST", body}).catch(() => {}));
}

async function start(opts) {
	const list = await fetch("assets.json").then((r) => (r.ok ? r.json() : []), () => []);
	await Promise.all(list.map(async (p) => {
		const r = await fetch(`assets/${p}`);
		if (r.ok) assets.set(p, new Uint8Array(await r.arrayBuffer()));
	}));

	mem = new odin.WasmMemoryInterface();
	mem.setIntSize(4);
	const all = odin.setupDefaultImports(mem);
	if (opts.devLog) {
		const write = all.odin_env.write;
		all.odin_env.write = (fd, p, n) => { write(fd, p, n); devLog(mem.loadString(p, n)); };
		window.addEventListener("error", (e) => devLog(`nv: ${e.message} (${e.filename}:${e.lineno})\n`));
		window.addEventListener("unhandledrejection", (e) => devLog(`nv: ${e.reason}\n`));
	}
	all.nv = imports;

	const bytes = await fetch(opts.wasm).then((r) => r.arrayBuffer());
	const {instance} = await WebAssembly.instantiate(bytes, all);
	ex = instance.exports;
	mem.setExports(ex);
	if (ex.memory) mem.setMemory(ex.memory);

	history.replaceState({nv: 0}, "");
	window.addEventListener("popstate", onPopState);
	darkQuery.addEventListener("change", () => event(EV.THEME, 0, 0));

	// main runs nv.run, which builds the root page and returns; the app then lives on events.
	// _end (the runtime's teardown) is never called: the page is the process.
	ex._start();
}

// liveElements: the ids nv holds, for spotting a leak from the console (it returns to the same
// number after a push and pop).
window.nv = {start, liveElements: () => els.length - 1 - freeIds.length};

})();
