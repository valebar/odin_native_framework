#+build js
package nv

// Web backend (HTML / CSS / JS, `-target:js_wasm32`): the DOM is the native toolkit. The wasm calls
// the "nv" import module of nv/web/nv.js, which creates, styles and appends elements and draws on
// <canvas>; nv/web/nv.css lays them out (Row / Column are flexboxes, an overlay a one-cell grid).
// A View is an element id in nv.js's table (never 0). Whoever creates an element releases it
// (web_create registers that with the current scope), which also takes it out of the document;
// parents only hold DOM children. Events come back through the exports at the bottom of this file
// (nv_web_*), which restore the Odin context and call the core's notifies. The rest is in the
// *_web.odin files (`#+build js`); nvbuild packages it (build/web: index.html, nv.js, nv.css, the
// compiler's odin.js, app.wasm and the assets) and serves it.

import "base:runtime"
import "core:fmt"

foreign import nv_js "nv"

// An element id in nv.js's table; 0 is none.
@(private) Web_Id :: distinct u32

// The kinds nv.js reports through nv_web_event (EV in nv.js).
@(private) Web_Event :: enum i32 {
	Button, Input_Change, Input_Submit, Action, Back, Menu, Fab, Scrim, Tab, List_Select, Theme,
}

// The icon nv.js draws for the bar's back button, after the nv.Icon ones.
@(private) WEB_ICON_BACK :: len(Icon) // nv.js's ICONS: one path per Icon, then the back arrow

@(private, default_calling_convention = "contextless")
foreign nv_js {
	// Elements
	js_app            :: proc() -> Web_Id ---
	js_create         :: proc(tag, class: string) -> Web_Id ---
	js_release        :: proc(id: Web_Id) ---
	js_append         :: proc(parent, child: Web_Id) ---
	js_label          :: proc(class: string) -> Web_Id --- // a box around a span; js_text sets the span's
	js_text           :: proc(id: Web_Id, text: string) ---
	js_style          :: proc(id: Web_Id, property, value: string) ---
	js_attr           :: proc(id: Web_Id, name, value: string) ---
	js_class          :: proc(id: Web_Id, class: string, on: b32) ---
	js_hidden         :: proc(id: Web_Id, hidden: b32) ---
	js_inert          :: proc(id: Web_Id, inert: b32) ---
	js_focus          :: proc(id: Web_Id) ---
	js_icon           :: proc(id: Web_Id, icon: i32) ---
	js_listen         :: proc(id: Web_Id, kind: Web_Event, h: rawptr, arg: i32) ---
	js_value          :: proc(id: Web_Id, buf: []u8) -> int --- // the value's length in bytes; copied if it fits
	js_set_value      :: proc(id: Web_Id, text: string) ---

	// The document
	js_title          :: proc(title: string) ---
	js_root_style     :: proc(property, value: string) ---
	js_color_scheme   :: proc(dark: b32) ---
	js_history        :: proc(depth: i32) ---
	js_show_page      :: proc() --- // a page below came back: draws its canvases

	// List and canvas
	js_list_create    :: proc(h: ^List_Handle, row_height: f64) -> Web_Id ---
	js_list_count     :: proc(id: Web_Id, count: i32) ---
	js_canvas_create  :: proc(h: ^Canvas_Handle) -> Web_Id ---
	js_canvas_redraw  :: proc(id: Web_Id) ---
	js_fill_rect      :: proc(x, y, w, h: f64, argb: u32) ---
	js_stroke_rect    :: proc(x, y, w, h: f64, argb: u32, width: f64) ---
	js_line           :: proc(x0, y0, x1, y1: f64, argb: u32, width: f64) ---
	js_fill_ellipse   :: proc(x, y, w, h: f64, argb: u32) ---
	js_stroke_ellipse :: proc(x, y, w, h: f64, argb: u32, width: f64) ---
	js_arc            :: proc(cx, cy, r, start, sweep: f64, argb: u32, width: f64) ---
	js_draw_text      :: proc(text: string, x, y, size: f64, weight: i32, italic: b32, font: i32, argb: u32) ---
	js_measure_text   :: proc(text: string, size: f64, weight: i32, italic: b32, font: i32) -> f64 ---
	js_text_height    :: proc(size: f64, weight: i32, italic: b32, font: i32) -> f64 ---
	js_draw_image     :: proc(bitmap: i32, x, y, w, h: f64) ---

	// Bitmaps, fonts, assets, downloads, timers
	js_bitmap         :: proc(data: []u8) -> i32 ---
	js_bitmap_release :: proc(bitmap: i32) ---
	js_image_set      :: proc(img: Web_Id, bitmap: i32, fit: i32) ---
	js_font           :: proc(data: []u8, weight: i32, italic: b32) -> i32 --- // 0 if the browser refused it
	js_font_release   :: proc(font: i32) ---
	js_asset_size     :: proc(path: string) -> int --- // -1 when missing
	js_asset_copy     :: proc(path: string, buf: []u8) ---
	js_fetch          :: proc(url: string, f: ^Fetch) ---
	js_timeout        :: proc(ms: i32, t: ^Timer) ---

	// The theme
	js_system_dark    :: proc() -> b32 ---
	js_system_accent  :: proc() -> u32 --- // 0xAARRGGBB, 0 when the browser has none
}

@(private) g_web: struct {
	ctx:     runtime.Context,
	app:     Web_Id, // #nv-app in index.html: the bar over the pages; dialogs on top
	bar:     Web_Id,
	back:    Web_Id, // the bar's back button, shown on pushed pages
	menu:    Web_Id, // the bar's menu button, shown when nav_shows_menu
	title:   Web_Id,
	actions: Web_Id, // holds the top page's action buttons
	buttons: [dynamic]Web_Id, // those buttons
	pages:   Web_Id, // one .nv-page per page on the stack
}

@(private)
web_view :: #force_inline proc "contextless" (id: Web_Id) -> View {
	return View(uintptr(id))
}

@(private)
web_id :: #force_inline proc "contextless" (v: View) -> Web_Id {
	return Web_Id(uintptr(v))
}

// An element that dies with the current scope.
@(private)
web_create :: proc(tag: string, class := "") -> Web_Id {
	id := js_create(tag, class)
	scope_on_dispose(web_release, rawptr(uintptr(id)))
	return id
}

@(private)
web_release :: proc(data: rawptr) {
	js_release(Web_Id(uintptr(data)))
}

@(private)
web_px :: proc(v: f64) -> string {
	return fmt.tprintf("%.2fpx", v)
}

// CSS's order: top, right, bottom, left.
@(private)
web_insets :: proc(i: Insets) -> string {
	return fmt.tprintf("%.2fpx %.2fpx %.2fpx %.2fpx", i.top, i.right, i.bottom, i.left)
}

@(private)
web_color :: proc(c: Color) -> string {
	a := color_argb(c)
	return fmt.tprintf("rgba(%d, %d, %d, %.3f)", a >> 16 & 0xff, a >> 8 & 0xff, a & 0xff, clamp(c.a, 0, 1))
}

@(private)
web_weight :: proc "contextless" (w: Weight) -> int {
	switch w {
	case .Default, .Regular: return 400
	case .Medium:            return 500
	case .Semibold:          return 600
	case .Bold:              return 700
	}
	return 400
}

// The CSS family of a loaded font (nv.js registers it as nv-font-<id>), the system font after it.
@(private)
web_font_family :: proc(f: ^Font) -> string {
	return fmt.tprintf("\"nv-font-%d\", var(--nv-font)", int(uintptr(f.native)))
}

// A Text_Style as inline CSS over the element's own (the class's) font; a zero field keeps it. A
// loaded face pins its own weight and slant, unless the style asks for others.
@(private)
web_style_text :: proc(id: Web_Id, s: Text_Style) {
	if s.size > 0 do js_style(id, "font-size", web_px(s.size))
	italic := s.italic
	if f := s.font; f != nil {
		js_style(id, "font-family", web_font_family(f))
		if s.weight == .Default do js_style(id, "font-weight", fmt.tprint(f.weight))
		italic ||= f.italic
	}
	if s.weight != .Default do js_style(id, "font-weight", fmt.tprint(web_weight(s.weight)))
	if italic do js_style(id, "font-style", "italic")
	if s.color.a > 0 do js_style(id, "color", web_color(s.color))
}

// ---- entry points from nv.js ----

// Clicks, edits and the like. The whole call is one callback (nv.js runs it from a DOM event).
@(private, export)
nv_web_event :: proc "c" (kind: Web_Event, h: rawptr, arg: i32) {
	context = g_web.ctx
	callback_enter()
	defer callback_exit()
	switch kind {
	case .Button:
		b := (^Button_Handle)(h)
		context = b.ctx
		button_notify(b)
	case .Input_Change:
		i := (^Input_Handle)(h)
		context = i.ctx
		input_notify(i, i.input.on_change)
	case .Input_Submit:
		i := (^Input_Handle)(h)
		context = i.ctx
		input_notify(i, i.input.on_submit)
	case .Action:
		a := (^Action_Handle)(h)
		context = a.ctx
		action_notify(a)
	case .Back:
		nav_back_notify()
	case .Menu:
		nav_menu_notify()
	case .Fab:
		f := (^Fab_Handle)(h)
		context = f.ctx
		fab_notify(f)
	case .Scrim:
		o := (^Overlay_Handle)(h)
		context = o.ctx
		overlay_scrim_notify(o)
	case .Tab:
		t := (^Tabbar_Handle)(h)
		context = t.ctx
		web_tab_clicked(t, int(arg))
	case .List_Select:
		l := (^List_Handle)(h)
		context = l.ctx
		if l.list.on_select != nil do list_select(l, int(arg))
	case .Theme:
		if g_theme.mode == .System {
			_theme_apply_mode()
			theme_notify()
		}
	}
}

// A list row came into view; `fresh` when nv.js made its elements just now.
@(private, export)
nv_web_list_bind :: proc "c" (h: ^List_Handle, index: i32, title, subtitle: Web_Id, fresh: b32) {
	context = h.ctx
	callback_enter()
	defer callback_exit()
	if fresh {
		h.cells_created += 1
		web_style_text(title, h.list.title_style)
		web_style_text(subtitle, h.list.subtitle_style)
	}
	item := list_item(h, int(index))
	js_text(title, item.title)
	js_text(subtitle, item.subtitle)
}

@(private, export)
nv_web_draw :: proc "c" (h: ^Canvas_Handle, width, height: f64) {
	context = h.ctx
	canvas_draw_notify(h, nil, width, height)
}

@(private, export)
nv_web_pointer :: proc "c" (h: ^Canvas_Handle, kind: i32, x, y: f64) {
	context = h.ctx
	canvas_pointer_notify(h, Pointer(kind), x, y)
}

// A wheel event in points; false without on_scroll, so the page scrolls instead.
@(private, export)
nv_web_scroll :: proc "c" (h: ^Canvas_Handle, dx, dy: f64) -> b32 {
	context = h.ctx
	if h.canvas.on_scroll == nil do return false
	canvas_scroll_notify(h, dx, dy)
	return true
}

// A buffer for bytes nv.js hands over (a download), on the heap like Fetch.data.
@(private, export)
nv_web_alloc :: proc "c" (n: i32) -> rawptr {
	context = g_web.ctx
	return raw_data(make([]u8, int(max(n, 0)), nv_heap()))
}

// A download finished: `n` bytes at `data` (from nv_web_alloc), or n < 0 on failure.
@(private, export)
nv_web_fetched :: proc "c" (f: ^Fetch, data: rawptr, n: i32) {
	context = f.ctx
	if n >= 0 do f.data = ([^]u8)(data)[:n]
	fetch_notify(f)
}

@(private, export)
nv_web_timer :: proc "c" (t: ^Timer) {
	timer_fire(t)
}

// The navigation depth, which nv.js keeps the browser history in step with.
@(private, export)
nv_web_depth :: proc "c" () -> i32 {
	return i32(len(g_nav) - 1)
}
