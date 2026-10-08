#+build windows
package nv

// Windows scaffold backend. Win32 has no overlay, FAB or bottom tab bar, so the pieces are windows
// of their own: an "NVOverlay" places its base full-size and its other children by their
// Overlay_Place on WM_SIZE and keeps them above the base in add order (every child has
// WS_CLIPSIBLINGS, so the z-order is also the paint order); the scrim is the dialog's layered
// "NVScrim" with the overlay in GWLP_USERDATA, which reports a click; the FAB ("NVFab") and the tab
// bar ("NVTabbar") are painted with GDI+ (shapes) and GDI (the MDL2 glyphs and the text). The
// timer is SetTimer on the main window, whose WM_TIMER (app_windows.odin) fires it.

import win "core:sys/windows"

@(private) CLASS_OVERLAY :: "NVOverlay"
@(private) CLASS_FAB     :: "NVFab"
@(private) CLASS_TABBAR  :: "NVTabbar"

@(private) FAB_SIZE :: 56.0 // dp

// The overlay's children and where they go (Overlay_Handle.native, in the scope's arena).
@(private) Windows_Overlay :: struct {
	children: [dynamic]Windows_Overlay_Child,
}

@(private) Windows_Overlay_Child :: struct {
	view:  win.HWND,
	place: Overlay_Place,
}

// Hiding or showing a child changes its parent's layout: a hidden child of a Row / Column takes no
// space (flex_layout skips it), and an overlay places the children it shows.
@(private)
_view_set_hidden :: proc(v: View, hidden: bool) {
	hwnd := win.HWND(v)
	if window_shown(hwnd) == !hidden do return
	win.ShowWindow(hwnd, hidden ? win.SW_HIDE : win.SW_SHOW)
	flex_relayout_ancestors(hwnd)
}

// EnableWindow disables the children too, and a disabled window takes neither clicks nor the focus.
@(private)
_view_set_enabled :: proc(v: View, enabled: bool) {
	hwnd := win.HWND(v)
	if !enabled && win.IsChild(hwnd, win.GetFocus()) do win.SetFocus(g_windows.parking)
	win.EnableWindow(hwnd, win.BOOL(enabled))
}

// Whether the window itself is set visible (WS_VISIBLE), whatever its parents are.
@(private)
window_shown :: proc "contextless" (hwnd: win.HWND) -> bool {
	return win.GetWindowLongPtrW(hwnd, win.GWL_STYLE) & win.LONG_PTR(win.WS_VISIBLE) != 0
}

@(private)
window_add_style :: proc "contextless" (hwnd: win.HWND, style: win.DWORD) {
	win.SetWindowLongPtrW(hwnd, win.GWL_STYLE, win.GetWindowLongPtrW(hwnd, win.GWL_STYLE) | win.LONG_PTR(style))
}

@(private)
_overlay_init :: proc(h: ^Overlay_Handle) {
	o := scope_new_in(Windows_Overlay)
	o.children = make([dynamic]Windows_Overlay_Child, scope_allocator(scope_current()))
	h.native = o
	wnd := win.CreateWindowExW(0, wstr(CLASS_OVERLAY), nil, win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPCHILDREN,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, h)
	base := win.HWND(h.base)
	window_add_style(base, win.WS_CLIPSIBLINGS)
	win.SetParent(base, wnd)
	h.root = View(wnd)
}

@(private)
_overlay_add :: proc(h: ^Overlay_Handle, child: View, place: Overlay_Place) {
	hwnd := win.HWND(child)
	window_add_style(hwnd, win.WS_CLIPSIBLINGS)
	win.SetParent(hwnd, win.HWND(h.root))
	append(&(^Windows_Overlay)(h.native).children, Windows_Overlay_Child{hwnd, place})
	overlay_layout(win.HWND(h.root))
}

@(private)
_overlay_place :: proc(h: ^Overlay_Handle, child: View, place: Overlay_Place) {
	for &c in (^Windows_Overlay)(h.native).children do if c.view == win.HWND(child) do c.place = place
	overlay_layout(win.HWND(h.root))
}

@(private)
_overlay_scrim_init :: proc(h: ^Overlay_Handle) {
	scrim := win.CreateWindowExW(win.WS_EX_LAYERED, wstr(CLASS_SCRIM), nil,
		win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPSIBLINGS, 0, 0, 0, 0, win.HWND(h.root), nil, g_windows.hinstance, nil)
	win.SetLayeredWindowAttributes(scrim, 0, SCRIM_ALPHA, win.LWA_ALPHA)
	win.SetWindowLongPtrW(scrim, win.GWLP_USERDATA, win.LONG_PTR(uintptr(h))) // scrim_proc reports the click
	append(&(^Windows_Overlay)(h.native).children, Windows_Overlay_Child{scrim, {h = .Fill, v = .Fill}})
	h.scrim = View(scrim)
	overlay_layout(win.HWND(h.root))
}

@(private)
overlay_handle_of :: proc "contextless" (hwnd: win.HWND) -> ^Overlay_Handle {
	return (^Overlay_Handle)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
}

// The base fills the client area; each shown child gets its place, then is raised in add order.
@(private)
overlay_layout :: proc(hwnd: win.HWND) {
	h := overlay_handle_of(hwnd)
	if h == nil || h.native == nil do return
	rc: win.RECT
	win.GetClientRect(hwnd, &rc)
	win.MoveWindow(win.HWND(h.base), 0, 0, rc.right, rc.bottom, true)
	for c in (^Windows_Overlay)(h.native).children {
		if !window_shown(c.view) do continue
		p := c.place
		m := [4]i32{px(p.margin.left), px(p.margin.top), px(p.margin.right), px(p.margin.bottom)}
		natural: [2]i32
		if (p.h != .Fill && p.width <= 0) || (p.v != .Fill && p.height <= 0) do natural = measure(c.view)
		x, w := overlay_axis(p.h, m[0], rc.right - m[2], p.width, natural.x)
		y, hh := overlay_axis(p.v, m[1], rc.bottom - m[3], p.height, natural.y)
		win.MoveWindow(c.view, x, y, w, hh, true)
		win.SetWindowPos(c.view, nil, 0, 0, 0, 0, win.SWP_NOMOVE | win.SWP_NOSIZE | win.SWP_NOACTIVATE) // HWND_TOP
	}
}

// One axis of a place between `start` and `end` (px): `size` dp, else `natural` px; Fill stretches.
@(private)
overlay_axis :: proc "contextless" (a: Align, start, end: i32, size: f64, natural: i32) -> (pos, length: i32) {
	avail := max(end - start, 0)
	length = a == .Fill ? avail : (size > 0 ? px(size) : natural)
	switch a {
	case .Start, .Fill: pos = start
	case .Center:       pos = start + (avail - length) / 2
	case .End:          pos = end - length
	}
	return
}

@(private)
overlay_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	if msg == win.WM_NCCREATE {
		cs := (^win.CREATESTRUCTW)(uintptr(lparam))
		win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(cs.lpCreateParams)))
	}
	h := overlay_handle_of(hwnd)
	if h == nil do return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	context = h.ctx

	switch msg {
	case win.WM_SIZE:
		callback_enter() // the base's and the children's Row / Column lay out inside these MoveWindows
		defer callback_exit()
		overlay_layout(hwnd)
		return 0
	case win.WM_CTLCOLORSTATIC: // a bare label as the base
		return ctlcolor_static(wparam, lparam)
	case win.WM_CTLCOLORBTN:
		return ctlcolor_button(lparam)
	case win.WM_ERASEBKGND:
		return erase_background(hwnd, win.HDC(wparam))
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

@(private)
_fab_init :: proc(h: ^Fab_Handle) {
	wnd := win.CreateWindowExW(0, wstr(CLASS_FAB), nil, win.WS_CHILD | win.WS_VISIBLE,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, h)
	h.root = View(wnd)
	h.control = rawptr(wnd)
}

@(private)
fab_handle_of :: proc "contextless" (hwnd: win.HWND) -> ^Fab_Handle {
	return (^Fab_Handle)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
}

// The glyph, unless there is no icon font or no glyph for the icon.
@(private)
fab_glyph :: proc "contextless" (h: ^Fab_Handle) -> string {
	return g_windows.icon_font != nil ? mdl2_glyphs[h.fab.icon] : ""
}

// Natural size in px: a 56dp circle, or 56dp high around the glyph and the label (extended).
@(private)
fab_measure :: proc(hwnd: win.HWND) -> [2]i32 {
	h := fab_handle_of(hwnd)
	size := px(FAB_SIZE)
	if h == nil || h.fab.label == "" do return {size, size}
	dc := win.GetDC(hwnd)
	defer win.ReleaseDC(hwnd, dc)
	w := text_size(dc, g_windows.font, h.fab.label).cx + 2 * px(20)
	if glyph := fab_glyph(h); glyph != "" do w += text_size(dc, g_windows.icon_font, glyph).cx + px(8)
	return {max(w, size), size}
}

@(private)
fab_paint :: proc(hwnd: win.HWND, h: ^Fab_Handle) {
	ps: win.PAINTSTRUCT
	dc := win.BeginPaint(hwnd, &ps)
	defer win.EndPaint(hwnd, &ps)
	rc: win.RECT
	win.GetClientRect(hwnd, &rc)
	if rc.right <= 0 || rc.bottom <= 0 do return

	mem := win.CreateCompatibleDC(dc)
	defer win.DeleteDC(mem)
	bmp := dib_section(rc.right, rc.bottom)
	defer win.DeleteObject(win.HGDIOBJ(bmp))
	old := win.SelectObject(mem, win.HGDIOBJ(bmp))
	defer win.SelectObject(mem, old)
	win.FillRect(mem, &rc, background_brush_of(win.GetParent(hwnd))) // the corners: what the overlay erases with

	g: GpGraphics
	GdipCreateFromHDC(mem, &g)
	GdipSetSmoothingMode(g, GP_SMOOTHING_ANTIALIAS)
	brush := with_brush(theme_palette().accent)
	w, hh := f32(rc.right), f32(rc.bottom)
	if h.fab.label == "" {
		GdipFillEllipse(g, brush, 0, 0, w - 1, hh - 1)
	} else {
		path := rounded_rect_path(0, 0, w - 1, hh - 1, hh / 2)
		GdipFillPath(g, brush, path)
		GdipDeletePath(path)
	}
	GdipDeleteBrush(brush)
	GdipDeleteGraphics(g)

	win.SetBkMode(mem, .TRANSPARENT)
	win.SetTextColor(mem, win.RGB(255, 255, 255))
	glyph := fab_glyph(h)
	gw, lw: i32
	if glyph != "" do gw = text_size(mem, g_windows.icon_font, glyph).cx
	if h.fab.label != "" do lw = text_size(mem, g_windows.font, h.fab.label).cx
	gap := glyph != "" && h.fab.label != "" ? px(8) : 0
	x := (rc.right - gw - gap - lw) / 2
	if glyph != "" {
		text_out(mem, g_windows.icon_font, glyph, x, (rc.bottom - font_height(g_windows.icon_font)) / 2)
		x += gw + gap
	}
	if h.fab.label != "" {
		text_out(mem, g_windows.font, h.fab.label, x, (rc.bottom - font_height(g_windows.font)) / 2)
	} else if glyph == "" {
		text_out(mem, g_windows.title, "+", (rc.right - text_size(mem, g_windows.title, "+").cx) / 2, (rc.bottom - font_height(g_windows.title)) / 2)
	}
	win.BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, win.SRCCOPY)
}

@(private)
text_out :: proc(dc: win.HDC, font: win.HFONT, text: string, x, y: i32) {
	w := wstr(text)
	old := win.SelectObject(dc, win.HGDIOBJ(font))
	win.TextOutW(dc, x, y, w, i32(len(string16_of(w))))
	win.SelectObject(dc, old)
}

@(private)
fab_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	if msg == win.WM_NCCREATE {
		cs := (^win.CREATESTRUCTW)(uintptr(lparam))
		win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(cs.lpCreateParams)))
	}
	h := fab_handle_of(hwnd)
	if h == nil do return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	context = h.ctx

	switch msg {
	case win.WM_PAINT:
		fab_paint(hwnd, h)
		return 0
	case win.WM_ERASEBKGND: // WM_PAINT covers every pixel
		return 1
	case win.WM_SIZE:
		// Cut to the painted shape (a circle, or a pill for the extended FAB), so a click in the
		// corners reaches what is under them; the system owns the region.
		w, hgt := i32(win.LOWORD(lparam)), i32(win.HIWORD(lparam))
		r := min(w, hgt)
		win.SetWindowRgn(hwnd, CreateRoundRectRgn(0, 0, w + 1, hgt + 1, r, r), true)
		return 0
	case win.WM_LBUTTONDOWN:
		win.SetCapture(hwnd)
		return 0
	case win.WM_LBUTTONUP:
		if win.GetCapture() != hwnd do return 0
		win.ReleaseCapture()
		rc: win.RECT
		win.GetClientRect(hwnd, &rc)
		x, y := win.GET_X_LPARAM(lparam), win.GET_Y_LPARAM(lparam)
		if x >= 0 && y >= 0 && x < rc.right && y < rc.bottom do fab_notify(h)
		return 0
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

@(private)
_tabbar_init :: proc(h: ^Tabbar_Handle) {
	wnd := win.CreateWindowExW(0, wstr(CLASS_TABBAR), nil, win.WS_CHILD | win.WS_VISIBLE,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, h)
	h.root = View(wnd)
	h.control = rawptr(wnd)
}

@(private)
_tabbar_select :: proc(h: ^Tabbar_Handle) {
	win.InvalidateRect(win.HWND(h.control), nil, false)
}

@(private)
tabbar_handle_of :: proc "contextless" (hwnd: win.HWND) -> ^Tabbar_Handle {
	return (^Tabbar_Handle)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
}

// Natural height in px: the glyph line (when there is an icon font), the title line and padding;
// the width stretches.
@(private)
tabbar_measure :: proc "contextless" (_: win.HWND) -> [2]i32 {
	hgt := px(6) + font_height(g_windows.font) + px(6)
	if g_windows.icon_font != nil do hgt += font_height(g_windows.icon_font) + px(2)
	return {0, hgt}
}

@(private)
tabbar_paint :: proc(hwnd: win.HWND, h: ^Tabbar_Handle) {
	ps: win.PAINTSTRUCT
	dc := win.BeginPaint(hwnd, &ps)
	defer win.EndPaint(hwnd, &ps)
	rc: win.RECT
	win.GetClientRect(hwnd, &rc)
	if rc.right <= 0 || rc.bottom <= 0 do return

	mem := win.CreateCompatibleDC(dc)
	defer win.DeleteDC(mem)
	bmp := dib_section(rc.right, rc.bottom)
	defer win.DeleteObject(win.HGDIOBJ(bmp))
	old := win.SelectObject(mem, win.HGDIOBJ(bmp))
	defer win.SelectObject(mem, old)
	pal := theme_palette()
	win.FillRect(mem, &rc, g_theme_windows.surface)
	line := win.CreateSolidBrush(colorref(pal.separator))
	top := win.RECT{0, 0, rc.right, 1}
	win.FillRect(mem, &top, line)
	win.DeleteObject(win.HGDIOBJ(line))

	win.SetBkMode(mem, .TRANSPARENT)
	n := i32(len(h.tabs))
	for t, i in h.tabs {
		x0, x1 := rc.right * i32(i) / n, rc.right * i32(i + 1) / n
		win.SetTextColor(mem, colorref(i == h.selected ? pal.accent : pal.secondary_text))
		y := px(6)
		if g_windows.icon_font != nil {
			if glyph := mdl2_glyphs[t.icon]; glyph != "" {
				gw := text_size(mem, g_windows.icon_font, glyph).cx
				text_out(mem, g_windows.icon_font, glyph, x0 + (x1 - x0 - gw) / 2, y)
			}
			y += font_height(g_windows.icon_font) + px(2)
		}
		tw := text_size(mem, g_windows.font, t.title).cx
		text_out(mem, g_windows.font, t.title, x0 + (x1 - x0 - tw) / 2, y)
	}
	win.BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, win.SRCCOPY)
}

@(private)
tabbar_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	if msg == win.WM_NCCREATE {
		cs := (^win.CREATESTRUCTW)(uintptr(lparam))
		win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(cs.lpCreateParams)))
	}
	h := tabbar_handle_of(hwnd)
	if h == nil do return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	context = h.ctx

	switch msg {
	case win.WM_PAINT:
		tabbar_paint(hwnd, h)
		return 0
	case win.WM_ERASEBKGND:
		return 1
	case win.WM_LBUTTONDOWN: // a tab is selected by a press and a release on the same cell
		g_tabbar_pressed = tabbar_cell(hwnd, h, lparam)
		if g_tabbar_pressed >= 0 do win.SetCapture(hwnd)
		return 0
	case win.WM_LBUTTONUP:
		if win.GetCapture() != hwnd do return 0
		win.ReleaseCapture()
		cell := tabbar_cell(hwnd, h, lparam)
		if cell < 0 || cell != g_tabbar_pressed do return 0
		tabbar_notify(h, cell) // sets h.selected
		win.InvalidateRect(hwnd, nil, false) // the window outlives a pop from on_tab until WM_NV_DESTROY
		return 0
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

// The cell pressed in the tab bar that holds the capture.
@(private) g_tabbar_pressed := -1

// The tab under the pointer, or -1 outside the bar.
@(private)
tabbar_cell :: proc "contextless" (hwnd: win.HWND, h: ^Tabbar_Handle, lparam: win.LPARAM) -> int {
	rc: win.RECT
	win.GetClientRect(hwnd, &rc)
	x, y := win.GET_X_LPARAM(lparam), win.GET_Y_LPARAM(lparam)
	if rc.right <= 0 || x < 0 || y < 0 || x >= rc.right || y >= rc.bottom || len(h.tabs) == 0 do return -1
	return int(x * i32(len(h.tabs)) / rc.right)
}

// The timer's pointer is its id on the main window (window_proc's WM_TIMER).
@(private)
_post_delayed :: proc(ms: int, t: ^Timer) {
	win.SetTimer(g_windows.parking, win.UINT_PTR(uintptr(t)), win.UINT(max(ms, 1)), nil)
}
