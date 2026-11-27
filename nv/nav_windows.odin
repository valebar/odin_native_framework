#+build windows
#+private
package nv

// Windows navigation backend. Win32 has no navigation bar, so an "NVNav" host window fills the
// main window and draws one itself: a back button (on pushed pages), the page title and the
// page's action buttons in a strip above the page, shown when the page is pushed or has actions.
// The bar's buttons are owner-drawn and flat, like an AppBar's IconButtons: Material's icon at
// 24 dp (svg_path.odin, the back arrow included) filled with GDI+, or the title when the icon has
// no path, with a translucent circle (a pill for text) while pressed or keyboard-focused. Their
// window text is the title either way (screen readers read it). The bar title is in
// theme_bar_title, centred.
// The window caption follows the page title too. Pages below the top are hidden, not destroyed;
// a popped page (and a replaced action button) is destroyed once its own message (a Back
// button's BN_CLICKED) has been handled.

import "core:slice"
import win "core:sys/windows"

@(private) WM_NV_DESTROY :: win.WM_APP + 1 // lparam: the HWND to destroy; wparam: a ^Scope to retire after it, or 0

// Segoe MDL2 Assets glyphs by Icon (the FAB and the tab bar); "" shows the title as text.
@(private) mdl2_glyphs := [Icon]string{
	.None     = "",
	.Add      = "\uE710",
	.Edit     = "\uE70F",
	.Delete   = "\uE74D",
	.Search   = "\uE721",
	.Share    = "\uE72D",
	.Settings = "\uE713",
	.Refresh  = "\uE72C",
	.Done     = "\uE73E",
	.Info     = "\uE946",
	.More     = "\uE712",
	.Close    = "\uE711",
	.Menu     = "\uE700",
	.Home     = "\uE80F",
	.Star     = "\uE734",
	.Person   = "\uE77B",
	.Hub      = "", // no MDL2 hub glyph: the title shows
}

@(private)
nav_create_host :: proc(wnd: win.HWND) {
	host := win.CreateWindowExW(0, wstr(CLASS_NAV), nil, win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPCHILDREN,
		0, 0, 0, 0, wnd, nil, g_windows.hinstance, nil)
	g_windows.root = host

	// The bar's controls clip their siblings so that their repaints stay under a dialog reaching
	// into the bar.
	g_windows.nav_back = nav_button(host, "Back")
	g_windows.nav_menu = nav_button(host, "Menu")

	g_windows.nav_title = label_new("", host, win.SS_CENTERIMAGE | win.WS_CLIPSIBLINGS, g_windows.title)
}

// A hidden owner-drawn bar button (nav_draw_button) in the host, `title` its text.
@(private)
nav_button :: proc(host: win.HWND, title: string, style: u32 = 0) -> win.HWND {
	b := win.CreateWindowExW(0, wstr("Button"), wstr(title), win.WS_CHILD | win.WS_TABSTOP | win.WS_CLIPSIBLINGS | win.BS_OWNERDRAW | style,
		0, 0, 0, 0, host, nil, g_windows.hinstance, nil)
	win.SendMessageW(b, win.WM_SETFONT, win.WPARAM(uintptr(g_windows.font)), 0)
	return b
}

// The bar title's font: theme_bar_title over the title font.
@(private)
nav_title_font :: proc() -> win.HFONT {
	return style_font(theme_bar_title(), g_windows.title)
}

@(private)
nav_text :: proc(hwnd: win.HWND) -> string {
	buf: [512]u16
	n := win.GetWindowTextW(hwnd, &buf[0], len(buf))
	text, _ := win.utf16_to_utf8(buf[:n], context.temp_allocator)
	return text
}

// The Material path a bar button shows, "" for its text.
@(private)
nav_button_icon :: proc(b: win.HWND) -> string {
	if b == g_windows.nav_back do return MATERIAL_BACK_PATH
	if b == g_windows.nav_menu do return material_icon_paths[.Menu]
	if h := (^Action_Handle)(uintptr(win.GetWindowLongPtrW(b, win.GWLP_USERDATA))); h != nil {
		return material_icon_paths[h.action.icon]
	}
	return ""
}

// A bar button's width: `side` (square) for an icon, else its text with 12 dp on each side.
@(private)
nav_button_width :: proc(b: win.HWND, side: i32) -> i32 {
	if nav_button_icon(b) != "" do return side
	dc := win.GetDC(b)
	defer win.ReleaseDC(b, dc)
	return max(text_size(dc, g_windows.font, nav_text(b)).cx + px(24), side)
}

@(private)
nav_draw_button :: proc(dis: ^DRAWITEMSTRUCT) {
	dc, rc := dis.hDC, dis.rcItem
	win.FillRect(dc, &rc, background_brush_of(dis.hwndItem))
	palette := theme_palette()
	color := dis.itemState & ODS_DISABLED != 0 ? palette.secondary_text : palette.text
	pressed := dis.itemState & ODS_SELECTED != 0
	focused := dis.itemState & ODS_FOCUS != 0 && dis.itemState & ODS_NOFOCUSRECT == 0
	icon := nav_button_icon(dis.hwndItem)
	x, y := f32(rc.left), f32(rc.top)
	w, h := f32(rc.right - rc.left), f32(rc.bottom - rc.top)
	if pressed || focused || icon != "" {
		g: GpGraphics
		GdipCreateFromHDC(dc, &g)
		defer GdipDeleteGraphics(g)
		GdipSetSmoothingMode(g, GP_SMOOTHING_ANTIALIAS)
		GdipSetPixelOffsetMode(g, GP_PIXEL_OFFSET_HALF)
		if pressed || focused {
			ink := palette.text
			ink.a = pressed ? 0.16 : 0.10
			brush := with_brush(ink)
			defer GdipDeleteBrush(brush)
			if w <= h {
				GdipFillEllipse(g, brush, x, y, w, h)
			} else {
				path := rounded_rect_path(x, y, w, h, h / 2)
				GdipFillPath(g, brush, path)
				GdipDeletePath(path)
			}
		}
		if icon != "" {
			// The 24-unit icon at 24 dp, centred; SVG's nonzero rule is GDI+'s winding mode.
			Target :: struct {
				path:          GpPath,
				ox, oy, scale: f32,
				x, y:          f32, // the current point, in px
			}
			size := f32(px(24))
			t := Target{ox = x + (w - size) / 2, oy = y + (h - size) / 2, scale = size / 24}
			GdipCreatePath(GP_FILL_MODE_WINDING, &t.path)
			defer GdipDeletePath(t.path)
			svg_path_replay(icon, {
				user = &t,
				move_to = proc(u: rawptr, x, y: f32) {
					t := (^Target)(u)
					GdipStartPathFigure(t.path)
					t.x, t.y = t.ox + x * t.scale, t.oy + y * t.scale
				},
				line_to = proc(u: rawptr, x, y: f32) {
					t := (^Target)(u)
					nx, ny := t.ox + x * t.scale, t.oy + y * t.scale
					GdipAddPathLine(t.path, t.x, t.y, nx, ny)
					t.x, t.y = nx, ny
				},
				cubic_to = proc(u: rawptr, c1x, c1y, c2x, c2y, x, y: f32) {
					t := (^Target)(u)
					nx, ny := t.ox + x * t.scale, t.oy + y * t.scale
					GdipAddPathBezier(t.path, t.x, t.y, t.ox + c1x * t.scale, t.oy + c1y * t.scale, t.ox + c2x * t.scale, t.oy + c2y * t.scale, nx, ny)
					t.x, t.y = nx, ny
				},
				close = proc(u: rawptr) { GdipClosePathFigure((^Target)(u).path) },
			})
			brush := with_brush(color)
			defer GdipDeleteBrush(brush)
			GdipFillPath(g, brush, t.path)
			return
		}
	}
	win.SetBkMode(dc, .TRANSPARENT)
	win.SetTextColor(dc, colorref(color))
	old := win.SelectObject(dc, win.HGDIOBJ(g_windows.font))
	defer win.SelectObject(dc, old)
	format := win.DrawTextFormat(u32(win.DrawTextFormat.DT_CENTER) | u32(win.DrawTextFormat.DT_VCENTER) | u32(win.DrawTextFormat.DT_SINGLELINE) | u32(win.DrawTextFormat.DT_NOPREFIX))
	win.DrawTextW(dc, wstr(nav_text(dis.hwndItem)), -1, &rc, format)
}

// The page root was created as a child of `parking`; only it moves into the host, so the list,
// input and button containers inside keep the parent their controls cached. It gets
// WS_CLIPSIBLINGS so that its repaints stay under the dialog windows over it.
@(private)
_nav_push :: proc(e: ^Page_Handle) {
	root := win.HWND(e.root)
	win.SetWindowLongPtrW(root, win.GWL_STYLE, win.GetWindowLongPtrW(root, win.GWL_STYLE) | win.LONG_PTR(win.WS_CLIPSIBLINGS))
	win.SetParent(root, g_windows.root)
	if len(g_nav) > 1 do win.ShowWindow(win.HWND(g_nav[len(g_nav) - 2].root), win.SW_HIDE)
	nav_update_chrome(e)
	nav_layout(g_windows.root)
}

@(private)
_nav_pop :: proc(top, below: ^Page_Handle) -> bool {
	win.ShowWindow(win.HWND(top.root), win.SW_HIDE)
	win.ShowWindow(win.HWND(below.root), win.SW_SHOW)
	dialog_apply_modal() // `below` may have been left disabled by a modal dialog closed while it was under `top`
	nav_update_chrome(below)
	nav_layout(g_windows.root)
	win.SetFocus(g_windows.parking) // the focused control is about to be destroyed with `top`
	return true
}

@(private)
_nav_release :: proc(e: ^Page_Handle) {
	// The scope goes after the tree: DestroyWindow's WM_NCDESTROYs still read the widget handles.
	win.PostMessageW(g_windows.root, WM_NV_DESTROY, win.WPARAM(uintptr(e.scope)), win.LPARAM(uintptr(e.root)))
}

// The bar shows the top page only; a lower page's changes are picked up when it is shown again.
@(private)
_nav_title_changed :: proc(e: ^Page_Handle) {
	if e == g_nav[len(g_nav) - 1] do nav_set_title(e)
}

@(private)
_nav_actions_changed :: proc(e: ^Page_Handle) {
	if e != g_nav[len(g_nav) - 1] do return
	nav_rebuild_actions(e)
	nav_layout(g_windows.root)
}

@(private)
_nav_leading_changed :: proc(e: ^Page_Handle) {
	if e != g_nav[len(g_nav) - 1] do return
	nav_set_leading(e)
	win.ShowWindow(g_windows.nav_title, nav_bar_shown() ? win.SW_SHOW : win.SW_HIDE)
	nav_layout(g_windows.root)
}

// The leading view moves into the bar while its page is on top; otherwise it is parked, hidden,
// under its page's root, so it is destroyed with the page.
@(private)
nav_set_leading :: proc(e: ^Page_Handle) {
	v := win.HWND(e.bar_leading)
	if v == g_windows.nav_leading do return
	if old := g_windows.nav_leading; old != nil {
		win.ShowWindow(old, win.SW_HIDE)
		win.SetParent(old, g_windows.nav_leading_home)
	}
	g_windows.nav_leading, g_windows.nav_leading_home = v, win.HWND(e.root)
	if v == nil do return
	win.SetWindowLongPtrW(v, win.GWL_STYLE, win.GetWindowLongPtrW(v, win.GWL_STYLE) | win.LONG_PTR(win.WS_CLIPSIBLINGS))
	win.SetParent(v, g_windows.root)
	win.ShowWindow(v, win.SW_SHOW)
}

@(private)
nav_update_chrome :: proc(e: ^Page_Handle) {
	nav_set_title(e)
	nav_set_leading(e)
	nav_rebuild_actions(e)
	win.ShowWindow(g_windows.nav_back, len(g_nav) > 1 ? win.SW_SHOW : win.SW_HIDE)
	win.ShowWindow(g_windows.nav_menu, nav_shows_menu(e) ? win.SW_SHOW : win.SW_HIDE)
	win.ShowWindow(g_windows.nav_title, nav_bar_shown() ? win.SW_SHOW : win.SW_HIDE)
}

// The window caption and the bar title.
@(private)
nav_set_title :: proc(e: ^Page_Handle) {
	title := wstr(e.page.title)
	win.SetWindowTextW(g_windows.parking, title)
	win.SendMessageW(g_windows.nav_title, win.WM_SETFONT, win.WPARAM(uintptr(nav_title_font())), 0)
	win.SetWindowTextW(g_windows.nav_title, title)
}

// The old action buttons are hidden now and destroyed later: one of them may be inside its own
// BN_CLICKED. The focus leaves them first, or it would die with them.
@(private)
nav_rebuild_actions :: proc(e: ^Page_Handle) {
	if slice.contains(g_windows.nav_actions[:], win.GetFocus()) do win.SetFocus(g_windows.parking)
	for b in g_windows.nav_actions {
		win.ShowWindow(b, win.SW_HIDE)
		win.PostMessageW(g_windows.root, WM_NV_DESTROY, 0, win.LPARAM(uintptr(b)))
	}
	clear(&g_windows.nav_actions)
	for h in e.actions {
		b := nav_button(g_windows.root, h.action.title, win.WS_VISIBLE)
		win.SetWindowLongPtrW(b, win.GWLP_USERDATA, win.LONG_PTR(uintptr(h)))
		append(&g_windows.nav_actions, b)
	}
	win.ShowWindow(g_windows.nav_title, nav_bar_shown() ? win.SW_SHOW : win.SW_HIDE) // the bar may appear or vanish with the root's actions
}

@(private)
nav_bar_shown :: proc "contextless" () -> bool {
	top := g_nav[len(g_nav) - 1]
	return len(g_nav) > 1 || len(top.actions) > 0 || nav_shows_menu(top) || top.bar_leading != nil
}

// The bar, when shown, is the title font height plus padding, at least 48 dp: the back button at
// the left, the action buttons right-aligned in declared order, the title in between. The top
// page gets the rest, and its dialogs are placed over everything (dialog_layout).
@(private)
nav_layout :: proc(host: win.HWND) {
	if len(g_nav) == 0 do return
	rc: win.RECT
	win.GetClientRect(host, &rc)
	bar: i32 = 0
	if nav_bar_shown() {
		title_font := nav_title_font()
		bar = max(font_height(title_font) + px(12), px(48))
		lead: [2]i32
		if g_windows.nav_leading != nil {
			lead = measure(g_windows.nav_leading)
			bar = max(bar, lead.y + px(8))
		}
		side := bar - px(8) // a glyph button: square, 4 dp from the bar's edges
		x := px(4)
		if len(g_nav) > 1 {
			back_w := nav_button_width(g_windows.nav_back, side)
			win.MoveWindow(g_windows.nav_back, px(4), px(4), back_w, side, true)
			x = px(12) + back_w
		} else if nav_shows_menu(g_nav[0]) {
			win.MoveWindow(g_windows.nav_menu, px(4), px(4), side, side, true)
			x = px(12) + side
		}
		right := rc.right - px(4)
		#reverse for b in g_windows.nav_actions {
			w := nav_button_width(b, side)
			right -= w
			win.MoveWindow(b, right, px(4), w, side, true)
		}
		right -= px(4)
		if g_windows.nav_leading != nil {
			win.MoveWindow(g_windows.nav_leading, x, (bar - lead.y) / 2, lead.x, lead.y, true)
			x += lead.x + px(8)
		}
		// Centred over the whole bar, pushed aside only as far as the sides need.
		dc := win.GetDC(g_windows.nav_title)
		tw := text_size(dc, title_font, nav_text(g_windows.nav_title)).cx
		win.ReleaseDC(g_windows.nav_title, dc)
		start := clamp((rc.right - tw) / 2, x, max(right - tw, x))
		win.MoveWindow(g_windows.nav_title, start, 0, max(min(tw + px(2), right - start), 0), bar, true)
	}
	win.MoveWindow(win.HWND(g_nav[len(g_nav) - 1].root), 0, bar, rc.right, max(rc.bottom - bar, 0), true)
	dialog_layout(rc)
}

@(private)
nav_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	context = g_windows.ctx
	switch msg {
	case win.WM_SIZE:
		// Nested Row / Column get their WM_SIZE inside this layout's MoveWindow calls.
		callback_enter()
		defer callback_exit()
		nav_layout(hwnd)
		return 0
	case win.WM_COMMAND:
		// Only the bar's own buttons notify the host: a page's buttons notify their NVButton container.
		if win.HIWORD(u32(wparam)) == win.BN_CLICKED {
			sender := win.HWND(uintptr(lparam))
			if sender == g_windows.nav_back {
				nav_back_notify()
				return 0
			}
			if sender == g_windows.nav_menu {
				nav_menu_notify()
				return 0
			}
			if slice.contains(g_windows.nav_actions[:], sender) {
				action_notify((^Action_Handle)(uintptr(win.GetWindowLongPtrW(sender, win.GWLP_USERDATA))))
				return 0
			}
		}
	case win.WM_CTLCOLORSTATIC:
		return ctlcolor_static(wparam, lparam)
	case win.WM_CTLCOLORBTN:
		return ctlcolor_button(lparam)
	case win.WM_DRAWITEM:
		if dis := (^DRAWITEMSTRUCT)(uintptr(lparam)); dis.CtlType == ODT_BUTTON {
			nav_draw_button(dis)
			return 1
		}
	case win.WM_ERASEBKGND:
		return erase_background(hwnd, win.HDC(wparam))
	case WM_NV_DESTROY:
		win.DestroyWindow(win.HWND(uintptr(lparam)))
		scope_retire((^Scope)(uintptr(wparam)))
		return 0
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
