#+build windows
#+private
package nv

// Windows navigation backend. Win32 has no navigation bar, so an "NVNav" host window fills the
// main window and draws one itself: a back button (on pushed pages), the page title and the
// page's action buttons in a strip above the page, shown when the page is pushed or has actions.
// The window caption follows the page title too. Pages below the top are hidden, not destroyed;
// a popped page (and a replaced action button) is destroyed once its own message (a Back
// button's BN_CLICKED) has been handled.

import "core:slice"
import win "core:sys/windows"

@(private) WM_NV_DESTROY :: win.WM_APP + 1 // lparam: the HWND to destroy; wparam: a ^Scope to retire after it, or 0

// Segoe MDL2 Assets glyphs by Icon; "" shows the title as text.
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
	back := win.CreateWindowExW(0, wstr("Button"), wstr("← Back"),
		win.WS_CHILD | win.WS_TABSTOP | win.WS_CLIPSIBLINGS | win.BS_PUSHBUTTON,
		0, 0, 0, 0, host, nil, g_windows.hinstance, nil)
	win.SendMessageW(back, win.WM_SETFONT, win.WPARAM(uintptr(g_windows.font)), 0)
	theme_control(back)
	g_windows.nav_back = back

	menu_text, menu_font := "☰", g_windows.font // the glyph when the icon font is there
	if g_windows.icon_font != nil do menu_text, menu_font = mdl2_glyphs[.Menu], g_windows.icon_font
	menu := win.CreateWindowExW(0, wstr("Button"), wstr(menu_text),
		win.WS_CHILD | win.WS_TABSTOP | win.WS_CLIPSIBLINGS | win.BS_PUSHBUTTON,
		0, 0, 0, 0, host, nil, g_windows.hinstance, nil)
	win.SendMessageW(menu, win.WM_SETFONT, win.WPARAM(uintptr(menu_font)), 0)
	theme_control(menu)
	g_windows.nav_menu = menu

	g_windows.nav_title = label_new("", host, win.SS_CENTERIMAGE | win.WS_CLIPSIBLINGS, g_windows.title)
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
		text, font := h.action.title, g_windows.font
		if glyph := mdl2_glyphs[h.action.icon]; glyph != "" && g_windows.icon_font != nil {
			text, font = glyph, g_windows.icon_font
		}
		b := win.CreateWindowExW(0, wstr("Button"), wstr(text),
			win.WS_CHILD | win.WS_VISIBLE | win.WS_TABSTOP | win.WS_CLIPSIBLINGS | win.BS_PUSHBUTTON,
			0, 0, 0, 0, g_windows.root, nil, g_windows.hinstance, nil)
		win.SendMessageW(b, win.WM_SETFONT, win.WPARAM(uintptr(font)), 0)
		theme_control(b)
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

// The bar, when shown, is the title font height plus padding: the back button at the left, the
// action buttons right-aligned in declared order, the title in between. The top page gets the
// rest, and its dialogs are placed over everything (dialog_layout).
@(private)
nav_layout :: proc(host: win.HWND) {
	if len(g_nav) == 0 do return
	rc: win.RECT
	win.GetClientRect(host, &rc)
	bar: i32 = 0
	if nav_bar_shown() {
		bar = g_windows.title_h + px(12)
		lead: [2]i32
		if g_windows.nav_leading != nil {
			lead = measure(g_windows.nav_leading)
			bar = max(bar, lead.y + px(8))
		}
		x := px(8)
		if len(g_nav) > 1 {
			back_w := button_ideal_size(g_windows.nav_back).x
			win.MoveWindow(g_windows.nav_back, px(8), px(4), back_w, bar - px(8), true)
			x = px(16) + back_w
		} else if nav_shows_menu(g_nav[0]) {
			side := bar - px(8) // square, like an icon action
			win.MoveWindow(g_windows.nav_menu, px(8), px(4), side, side, true)
			x = px(16) + side
		}
		right := rc.right - px(8)
		#reverse for b in g_windows.nav_actions {
			ideal: win.SIZE
			win.Button_GetIdealSize(b, &ideal)
			w := ideal.cx + px(12)
			if win.HFONT(uintptr(win.SendMessageW(b, win.WM_GETFONT, 0, 0))) == g_windows.icon_font {
				w = max(ideal.cx + px(8), bar - px(8)) // at least square
			}
			right -= w
			win.MoveWindow(b, right, px(4), w, bar - px(8), true)
			right -= px(4)
		}
		if g_windows.nav_leading != nil {
			win.MoveWindow(g_windows.nav_leading, x, (bar - lead.y) / 2, lead.x, lead.y, true)
			x += lead.x + px(8)
		}
		// Centred over the whole bar, pushed aside only as far as the sides need.
		dc := win.GetDC(g_windows.nav_title)
		buf: [512]u16
		n := win.GetWindowTextW(g_windows.nav_title, &buf[0], len(buf))
		text, _ := win.utf16_to_utf8(buf[:n], context.temp_allocator)
		tw := text_size(dc, g_windows.title, text).cx
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
	case win.WM_ERASEBKGND:
		return erase_background(hwnd, win.HDC(wparam))
	case WM_NV_DESTROY:
		win.DestroyWindow(win.HWND(uintptr(lparam)))
		scope_retire((^Scope)(uintptr(wparam)))
		return 0
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
