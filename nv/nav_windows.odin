#+build windows
package nv

// Windows navigation backend. Win32 has no navigation bar, so an "NVNav" host window fills the
// main window and draws one itself: a back button (on pushed pages), the page title and the
// page's action buttons in a strip above the page, shown when the page is pushed or has actions.
// The window caption follows the page title too. Pages below the top are hidden, not destroyed;
// a popped page (and a replaced action button) is destroyed once its own message (a Back
// button's BN_CLICKED) has been handled.

import win "core:sys/windows"

@(private) WM_NV_DESTROY :: win.WM_APP + 1 // lparam: the HWND to destroy

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
}

@(private)
nav_create_host :: proc(wnd: win.HWND) {
	host := win.CreateWindowExW(0, wstr(CLASS_NAV), nil, win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPCHILDREN,
		0, 0, 0, 0, wnd, nil, g_windows.hinstance, nil)
	g_windows.root = host

	back := win.CreateWindowExW(0, wstr("Button"), wstr("← Back"),
		win.WS_CHILD | win.WS_TABSTOP | win.BS_PUSHBUTTON,
		0, 0, 0, 0, host, nil, g_windows.hinstance, nil)
	win.SendMessageW(back, win.WM_SETFONT, win.WPARAM(uintptr(g_windows.font)), 0)
	g_windows.nav_back = back

	g_windows.nav_title = label_new("", host, win.SS_CENTERIMAGE)
}

// The page root was created as a child of `parking`; only it moves into the host, so the list,
// input and button containers inside keep the parent their controls cached.
@(private)
_nav_push :: proc(e: ^Nav_Page) {
	win.SetParent(win.HWND(e.root), g_windows.root)
	if len(g_nav) > 1 do win.ShowWindow(win.HWND(g_nav[len(g_nav) - 2].root), win.SW_HIDE)
	nav_update_chrome(e)
	nav_layout(g_windows.root)
}

@(private)
_nav_pop :: proc(top, below: ^Nav_Page) -> bool {
	win.ShowWindow(win.HWND(top.root), win.SW_HIDE)
	win.ShowWindow(win.HWND(below.root), win.SW_SHOW)
	nav_update_chrome(below)
	nav_layout(g_windows.root)
	win.SetFocus(g_windows.parking) // the focused control is about to be destroyed with `top`
	return true
}

@(private)
_nav_release :: proc(e: ^Nav_Page) {
	win.PostMessageW(g_windows.root, WM_NV_DESTROY, 0, win.LPARAM(uintptr(e.root)))
}

@(private)
_nav_actions_changed :: proc(e: ^Nav_Page) {
	nav_update_chrome(e)
	nav_layout(g_windows.root)
}

// The old action buttons are hidden now and destroyed later: one of them may be inside its own
// BN_CLICKED.
@(private)
nav_update_chrome :: proc(e: ^Nav_Page) {
	title := wstr(e.page.title)
	win.SetWindowTextW(g_windows.parking, title)
	win.SetWindowTextW(g_windows.nav_title, title)

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
			win.WS_CHILD | win.WS_VISIBLE | win.WS_TABSTOP | win.BS_PUSHBUTTON,
			0, 0, 0, 0, g_windows.root, nil, g_windows.hinstance, nil)
		win.SendMessageW(b, win.WM_SETFONT, win.WPARAM(uintptr(font)), 0)
		win.SetWindowLongPtrW(b, win.GWLP_USERDATA, win.LONG_PTR(uintptr(h)))
		append(&g_windows.nav_actions, b)
	}

	win.ShowWindow(g_windows.nav_back, len(g_nav) > 1 ? win.SW_SHOW : win.SW_HIDE)
	win.ShowWindow(g_windows.nav_title, nav_bar_shown() ? win.SW_SHOW : win.SW_HIDE)
}

@(private)
nav_bar_shown :: proc "contextless" () -> bool {
	return len(g_nav) > 1 || len(g_nav[len(g_nav) - 1].actions) > 0
}

// The bar, when shown, is the title font height plus padding: the back button at the left, the
// action buttons right-aligned in declared order, the title in between. The top page gets the rest.
@(private)
nav_layout :: proc "contextless" (host: win.HWND) {
	if len(g_nav) == 0 do return
	rc: win.RECT
	win.GetClientRect(host, &rc)
	bar: i32 = 0
	if nav_bar_shown() {
		bar = g_windows.title_h + px(12)
		x := px(8)
		if len(g_nav) > 1 {
			back_w := button_ideal_size(g_windows.nav_back).x
			win.MoveWindow(g_windows.nav_back, px(8), px(4), back_w, bar - px(8), true)
			x = px(16) + back_w
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
		win.MoveWindow(g_windows.nav_title, x, 0, max(right - x, 0), bar, true)
	}
	win.MoveWindow(win.HWND(g_nav[len(g_nav) - 1].root), 0, bar, rc.right, max(rc.bottom - bar, 0), true)
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
				callback_enter()
				defer callback_exit()
				pop()
				return 0
			}
			if h := (^Action_Handle)(uintptr(win.GetWindowLongPtrW(sender, win.GWLP_USERDATA))); h != nil {
				action_notify(h)
				return 0
			}
		}
	case win.WM_CTLCOLORSTATIC:
		return ctlcolor_static(wparam)
	case WM_NV_DESTROY:
		win.DestroyWindow(win.HWND(uintptr(lparam)))
		return 0
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
