#+build windows
package nv

// Windows navigation backend. Win32 has no navigation bar, so an "NVNav" host window fills the
// main window and draws one itself on pushed pages: a back button and the page title in a strip
// above the page. The window caption follows the page title too. Pages below the top are hidden,
// not destroyed; a popped page is destroyed once its own message (a Back button's BN_CLICKED)
// has been handled.

import win "core:sys/windows"

@(private) WM_NV_DESTROY :: win.WM_APP + 1 // lparam: the HWND to destroy

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
nav_update_chrome :: proc(e: ^Nav_Page) {
	title := wstr(e.page.title)
	win.SetWindowTextW(g_windows.parking, title)
	win.SetWindowTextW(g_windows.nav_title, title)
	show := len(g_nav) > 1 ? win.SW_SHOW : win.SW_HIDE
	win.ShowWindow(g_windows.nav_back, show)
	win.ShowWindow(g_windows.nav_title, show)
}

// The bar, when shown, is the title font height plus padding; the top page gets the rest.
@(private)
nav_layout :: proc "contextless" (host: win.HWND) {
	if len(g_nav) == 0 do return
	rc: win.RECT
	win.GetClientRect(host, &rc)
	bar: i32 = 0
	if len(g_nav) > 1 {
		bar = g_windows.title_h + px(12)
		back_w := button_ideal_size(g_windows.nav_back).x
		win.MoveWindow(g_windows.nav_back, px(8), px(4), back_w, bar - px(8), true)
		x := px(16) + back_w
		win.MoveWindow(g_windows.nav_title, x, 0, max(rc.right - x - px(8), 0), bar, true)
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
		if win.HWND(uintptr(lparam)) == g_windows.nav_back && win.HIWORD(u32(wparam)) == win.BN_CLICKED {
			callback_enter()
			defer callback_exit()
			pop()
			return 0
		}
	case win.WM_CTLCOLORSTATIC:
		return ctlcolor_static(wparam)
	case WM_NV_DESTROY:
		win.DestroyWindow(win.HWND(uintptr(lparam)))
		return 0
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
